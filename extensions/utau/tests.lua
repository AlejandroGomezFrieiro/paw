-- Tests of the utau extension outside the vocal editor: curves that follow
-- their clips, export, freezing, singer presets, installing singers,
-- harmony and doubling, and the renderer's own features. Loaded by
-- tests/suite.lua with its helpers. Tests that sing need paw-utau-engine and
-- the test voicebank, and are skipped without them.
local T = ...
io.stdout:setvbuf("line")
local api = paw.api
local eq, near, test, fails = T.eq, T.near, T.test, T.fails

local SINGER = os.getenv("PAW_UTAU_TEST_SINGER") or "Kitane sno act5 VCV"

local utau
local function load()
  if not (paw.ext.loaded.utau and paw.ext.loaded.utau.ok) then paw.ext.load("extensions/utau") end
  utau = require("utau")
  return utau
end

--- The vocal editor is one view for all the tests: a test that changes the
--- curve under its notes puts the curve back when it ends.
local function keep_curve()
  local editor = require("utau.editor").editor
  local was = editor.curve
  T.after(function() editor.curve = was end)
end

--- Skip unless the engine runs and has the test voicebank.
local function need_singer()
  load()
  -- The voicebanks are read where PAW_UTAU_OPENUTAU_DIR says, never from
  -- a home folder the test did not name.
  if paw.opt.utau_openutau_dir == "" and not os.getenv("PAW_UTAU_OPENUTAU_DIR") then
    return "skipped: set PAW_UTAU_OPENUTAU_DIR to the OpenUtau folder with the test voicebank"
  end
  if not utau.engine.find() then return "skipped: paw-utau-engine not found (set PAW_UTAU_ENGINE)" end
  utau.engine.start()
  if not utau.wait(function() return #utau.singers > 0 end, 60) then
    return "skipped: paw-utau-engine did not start: " .. tostring(utau.engine.reason)
  end
  if not utau.find_singer(SINGER) or utau.find_singer(SINGER).id ~= SINGER then
    return "skipped: voicebank " .. SINGER .. " is not installed"
  end
end

local SYLLABLES = { "- あ", "- い", "- う", "- え", "- お" }

--- A vocal track with a clip of `pitches` from `at`, a beat each.
local function vocal(name, pitches, at)
  local track = paw.add_track({ name = name or "Vocal" })
  track:add_device(load().DEVICE)
  local list = {}
  for i, p in ipairs(pitches or { 60, 62, 64, 65 }) do
    list[i] = { pitch = p, start = i - 1, length = 1, meta = { lyric = SYLLABLES[(i - 1) % #SYLLABLES + 1] } }
  end
  local clip = track:add_clip({ start = at or 0, length = #list, notes = list, name = "verse" })
  return track, clip
end

local function curve(track, abbr, beat)
  return require("utau.notes").curve_at(track.id, utau.device_of(track.id), abbr, beat)
end

--- The track's dynamics and pitch at some beats, as text: "dyn@4=-50 ...".
local function curves(track, beats)
  local out = {}
  for _, b in ipairs(beats) do
    local function r(v) return math.floor(v * 10 + 0.5) / 10 end
    out[#out + 1] = string.format("%g:%g/%g", b, r(curve(track, "dyn", b)), r(curve(track, "pitd", b)))
  end
  return table.concat(out, " ")
end

--- A vocal track with a clip at beats 4..8 and curves drawn under it.
local function sung()
  T.fresh()
  load()
  local track, clip = vocal("Lead", { 60, 62, 64, 65 }, 4)
  local n = require("utau.notes")
  local device = utau.device_of(track.id)
  n.stroke(track.id, device, "dyn", { { 4, -50 }, { 6, 30 }, { 8, -20 } })
  n.stroke(track.id, device, "pitd", { { 5, 100 }, { 7, -100 } })
  paw.flush()
  api.undo_checkpoint()
  return track, clip
end

-- The device -----------------------------------------------------------------------

local ffi = require("ffi")

--- A sine of `freq` Hz lasting `seconds` at `rate`, as 32-bit floats.
local function sine(freq, seconds, rate)
  local n = math.floor(seconds * rate)
  local buf = ffi.new("float[?]", n)
  for i = 0, n - 1 do
    buf[i] = 0.5 * math.sin(2 * math.pi * freq * i / rate)
  end
  return ffi.string(buf, n * 4)
end

--- The left channel of a 32-bit render, as a float array counted from 0
--- (kept alive with the string it points into), and its length.
local function floats(info)
  local data = T.read_file(info.path)
  local at = data:find("data", 1, true) + 8
  local frames = math.floor((#data - at + 1) / 8)
  local all = ffi.cast("const float *", ffi.cast("const char *", data) + at - 1)
  local left = ffi.new("float[?]", frames)
  for i = 0, frames - 1 do
    left[i] = all[i * 2]
  end
  return left, frames
end

--- A vocal track with a clip and no notes: what it plays is what it is given.
local function voice_track(name)
  local track = paw.add_track({ name = name })
  track:add_device(load().DEVICE)
  track:add_clip({ start = 0, length = 8 })
  utau.assign_voices()
  return track, utau.device_of(track.id)
end

--- Run `fn` with the engine kept off, so that it does not sing over the
--- phrases a test gives a device itself.
local function without_engine(fn)
  load()
  local start = utau.engine.start
  utau.engine.stop()
  utau.engine.start = function() return false end
  local ok, err = pcall(fn)
  utau.engine.start = start
  if not ok then error(err, 0) end
end

test("utau: the device plays the phrases it is given, in time", function()
  T.fresh()
  load()
  paw.project.tempo = 120
  local t, device = voice_track("Voice")
  local v = utau.voices
  v.put(device, "11", 1.0, 44100, 1, 1, sine(330, 1.0, 44100))
  v.put(device, "12", 2.5, 44100, 1, 1, sine(440, 0.5, 44100))
  eq(#v.list(device), 2, "two phrases")
  v.put(device, "12", 2.5, 44100, 1, 0, sine(220, 0.5, 44100))
  eq(v.list(device)[2].quality, 1, "a draft does not replace final audio")
  fails(function() v.put(device, "1", 0, 44100, 1, 1, "abc") end, "whole frames", "bad audio")
  fails(function() api.device_call(device, "nothing") end, "no method", "unknown call")
  local info = T.render({ bits = 16, ["end"] = 8, tail = 0 })
  eq(T.channel_peaks(info, 0.1, 0.9) < 0.001, true, "silent before the first phrase")
  near(T.channel_peaks(info, 1.1, 1.9), 0.5, 0.02, "the first phrase plays at its time")
  near(T.frequency(info, 1.1, 1.9), 330, 5, "at its pitch")
  near(T.frequency(info, 2.55, 2.95), 440, 6, "the second at its own")
  eq(T.channel_peaks(info, 3.1, 3.9) < 0.001, true, "silent after")
  v.keep(device, { "12" })
  eq(#v.list(device), 1, "one kept")
  info = T.render({ bits = 16, ["end"] = 8, tail = 0 })
  eq(T.channel_peaks(info, 1.1, 1.9) < 0.001, true, "a phrase that is not kept is gone")
  -- In real time, too.
  paw.transport.seek(5)
  paw.transport.play()
  local loudest = 0
  T.until_(function()
    loudest = math.max(loudest, t:meter())
    return paw.transport.position >= 5.9
  end, "the playhead at beat 5.9")
  paw.transport.stop()
  eq(loudest > 0.2, true, "heard while playing")
  v.clear(device)
  eq(#v.list(device), 0, "cleared")
end, { live = "the meter of the track is read while the engine plays in real time" })

test("utau: a device made later, a render's own and the one playing live sound exactly the same", function()
  without_engine(function()
    T.fresh()
    load()
    paw.project.tempo = 120
    local first, device = voice_track("First")
    local voice = utau.voices.voice_of(device)
    local rate = T.render({ bits = 32, ["end"] = 1, tail = 0 }).sample_rate
    -- At the project's rate, so that what is played is the samples as given.
    local raw = sine(523.25, 1.5, rate)
    utau.voices.put(device, "7", 0.5, rate, 1, 1, raw)
    -- The track that was given the phrase goes; a new one takes its voice.
    first:remove()
    local track = paw.add_track({ name = "Later" })
    local later = track:add_device(utau.DEVICE, { voice = voice })
    track:add_clip({ start = 0, length = 8 })
    paw.flush()
    eq(utau.voices.voice_of(later.id), voice, "the new device has the voice")
    eq(#utau.voices.list(later.id), 1, "and knows its phrase, given before it was made")
    local given = ffi.cast("const float *", raw)
    local at = math.floor(0.5 * rate + 0.5)
    local count = math.floor(1.5 * rate)
    -- Live: what the device plays while the song plays, kept by the device.
    api.device_call(later.id, "capture", "0.25 2.25")
    paw.transport.seek(0)
    paw.transport.play()
    T.until_(function() return paw.transport.position > 4.6 end, "the song to play past 2.25 s", 10000)
    paw.transport.stop()
    local captured = api.device_call(later.id, "captured")
    local live = ffi.cast("const float *", captured)
    local from = math.floor(0.25 * rate + 0.5)
    local differ = 0
    for i = 0, count - 1 do
      if live[at - from + i] ~= given[i] then differ = differ + 1 end
    end
    eq(differ, 0, "live, the device plays the samples bit for bit as they were given")
    eq(live[at - from - 1], 0, "and nothing before them")
    -- The render's own device, through the track's fader and the master's:
    -- the render must be the samples given times the gain a fader has at its
    -- centre, twice, rounded as the mixer rounds.
    local left, frames = floats(T.render({ bits = 32, ["end"] = 6, tail = 0 }))
    eq(frames > at + count, true, "the render is long enough")
    local loudest = 0
    for i = 0, count - 1 do
      if math.abs(given[i]) > math.abs(given[loudest]) then loudest = i end
    end
    local g = ffi.new("union { float f; int32_t i; }")
    g.f = math.sqrt(left[at + loudest] / given[loudest])
    local base, matched = g.i, false
    local product = ffi.new("float[1]")
    for ulps = -4, 4 do
      g.i = base + ulps
      local all = true
      for i = 0, count - 1 do
        product[0] = given[i] * g.f
        product[0] = product[0] * g.f
        if product[0] ~= left[at + i] then
          all = false
          break
        end
      end
      matched = matched or all
    end
    eq(matched, true, "offline, the render's own device plays the same samples, bit for bit")
    eq(left[at - 1], 0, "and nothing before them")
  end)
end)

test("utau: a vocal track is a kind of track: made, shown, described and opened as one", function()
  T.fresh()
  load()
  paw.ui.focus("arrange")
  T.keys("<localleader>Vt")
  while paw.ui.float do
    paw.ui.close()
  end
  local track = paw.tracks()[#paw.tracks()]
  eq(paw.track_kinds.of(track.id), "vocal", "the key makes a vocal track")
  eq(utau.device_of(track.id) ~= nil, true, "with the singing device")
  utau.configure(track.id, { singer = "Someone" })
  eq(paw.track_kinds.describe(track.id), "Vocal track · Someone", "described with its singer")
  local screen = table.concat(api.ui_snapshot(120, 30), "\n")
  eq(screen:find(" V Vocal", 1, true) ~= nil, true, "the header shows V before the name, a column clear of it")
  local clip = track:add_clip({ start = 0, length = 2, notes = { { pitch = 60, start = 0, length = 1 } } })
  paw.cursor.set_track(track)
  paw.cursor.set_beat(0.5)
  paw.cmd("clip.edit")
  eq(paw.ui.focused, "utau", "clip.edit opens the vocal editor")
  eq(require("utau.editor").editor.clip_id, clip.id, "on the clip")
  paw.ui.hide("utau")
  paw.ui.focus("arrange")
  -- A vocal track from before there were kinds of track: it has the device.
  local old = paw.add_track({ name = "Old vocal" })
  old:add_device(utau.DEVICE)
  eq(paw.track_kinds.of(old.id), "vocal", "a track with the device is a vocal track")
  -- utau.voice makes the cursor track one, without asking for a singer.
  local plain = paw.add_track({ name = "Plain" })
  paw.cursor.set_track(plain)
  paw.cmd("utau.voice")
  eq(
    plain.meta.kind .. " " .. tostring(utau.device_of(plain.id) ~= nil),
    "vocal true",
    "utau.voice makes it a vocal track"
  )
end)

test("utau: a project saved when the device was built in sings with the Lua device", function()
  T.fresh()
  load()
  paw.project.tempo = 120
  local track = paw.add_track({ name = "Old" })
  local old = track:add_device(utau.voices.OLD_DEVICE)
  track:add_clip({ start = 0, length = 8 })
  eq(old:get().kind, "utau", "the device keeps the kind it was saved with")
  eq(utau.device_of(track.id), old.id, "and is the track's vocal device")
  utau.assign_voices()
  utau.voices.put(old.id, "31", 0.5, 44100, 1, 1, sine(440, 1, 44100))
  near(
    T.channel_peaks(T.render({ bits = 16, ["end"] = 4, tail = 0 }), 0.6, 1.4),
    0.5,
    0.02,
    "it sings what it is given"
  )
end)

test("utau: a vocal device that crashes is stopped alone, and started again sings its voice", function()
  T.fresh()
  load()
  paw.project.tempo = 120
  local _, device = voice_track("Voice")
  utau.voices.put(device, "21", 0.5, 44100, 1, 1, sine(440, 1, 44100))
  local pid = tonumber(api.device_call(device, "sandbox.pid"))
  eq(pid ~= api.env().pid, true, "the device runs in a process of its own")
  local stopped = {}
  local handler = paw.on("device.stopped", function(e) stopped[#stopped + 1] = e end)
  paw.transport.play()
  T.next_block(10)
  os.execute("kill -KILL " .. pid)
  T.until_(function() return #stopped > 0 end, "the crash to be told", 5000)
  paw.transport.stop()
  paw.off(handler)
  eq(stopped[1].device, device, "the vocal device is the one stopped")
  eq(#paw.tracks(), 1, "the session goes on")
  paw.device(device):restart()
  eq(paw.device(device):get().stopped, nil, "started again")
  eq(#utau.voices.list(device), 1, "it was given its voice again")
  near(T.channel_peaks(T.render({ bits = 16, ["end"] = 4, tail = 0 }), 0.6, 1.4), 0.5, 0.02, "and sings it")
end)

test("utau: where phrases overlap, the vocal device sounds them together", function()
  load()
  -- The device's own code, run here on a block of its own.
  local dev = assert(loadfile("extensions/utau/devices/utau.lua"))()
  local rate, frames = 48000, 512
  dev.init(rate)
  local lines = {}
  for k = 0, 7 do
    local path = utau.voices.dir() .. "/overlap-" .. k .. ".f32"
    T.write_file(path, sine(220 + k * 30, 2, 44100))
    lines[#lines + 1] = string.format("b%d %g 44100 1 1 %s", k, k * 0.25, path)
  end
  dev.call("voice.1", table.concat(lines, "\n"))
  T.after(function() dev.call("voice.1", "") end)
  local b = {
    left = ffi.new("float[?]", frames),
    right = ffi.new("float[?]", frames),
    frames = frames,
    params = { voice = 1 },
    sample_rate = rate,
    playing = true,
    tempo = 120,
    -- Five phrases sound at 1.1 s: those that start at 0, 0.25, 0.5, 0.75 and 1 s.
    seconds = 1.1,
  }
  dev.process(b)
  local peak = 0
  for i = 0, frames - 1 do
    peak = math.max(peak, math.abs(b.left[i]))
  end
  -- One phrase alone peaks at 0.5.
  eq(peak > 0.5, true, "the phrases sound together: the peak is " .. peak)
end)

-- The vocal editor in pictures -----------------------------------------------------

--- The heights a drawing's lines reach between two x, in pixels: lowest and highest.
local function reach(ops, colour, x0, x1)
  local lo, hi
  for _, op in ipairs(ops) do
    if op[1] == "p" and op[3] == colour then
      for x, y in op[2]:gmatch("[ML] ([%d.-]+) ([%d.-]+)") do
        x, y = tonumber(x), tonumber(y)
        if x >= x0 and x <= x1 then
          lo, hi = math.min(lo or y, y), math.max(hi or y, y)
        end
      end
    end
  end
  return lo, hi
end

test("utau: where the terminal shows pictures the pitch and the curve are strips under the notes", function()
  T.fresh()
  load()
  local track, clip = vocal("Lead", { 60, 62, 64, 65 })
  local notes = require("utau.notes")
  -- The second note sings a vibrato 25 cents deep over its last half.
  notes.change_props(clip.id, function(p)
    p.vb = { 50, 175, 25, 0, 0, 0, 0, 0 }
    return true
  end, { [2] = true })
  notes.stroke(track.id, utau.device_of(track.id), "dyn", { { 0, -50 }, { 2, 30 }, { 4, -20 } })
  paw.flush()
  local editor = require("utau.editor").editor
  editor:edit(clip.id)
  keep_curve()
  editor.curve = "dyn"
  local W, H = 120, 36
  local cells = api.ui_snapshot(W, H)
  eq(paw.ui.rects.surfaces, nil, "no pictures: cells")

  api.ui_caps_set({ graphics = true, cell = { w = 10, h = 20 }, under = true })
  T.after(function() api.ui_caps_set({ graphics = false, cell = { w = 0, h = 0 } }) end)
  api.ui_snapshot(W, H)
  local strips = {}
  for _, s in ipairs(paw.ui.rects.surfaces or {}) do
    strips[s.key:match("^utau:(%a+)#")] = s
  end
  eq(strips.roll ~= nil and strips.curve ~= nil, true, "a strip for the roll and one for the curve")
  eq(strips.roll.under and strips.curve.under, true, "under the cells")
  local function ops_of(s) return paw.canvas.draw(s.draw, { w = s.w * 10, h = s.h * 20, cell = { w = 10, h = 20 } }) end
  local roll = ops_of(strips.roll)
  local P = require("paw.theme").palette
  local ppb = paw.opt.note_zoom * 10
  -- The vibrato swings 25 cents either side: half a row of 20 pixels from
  -- top to bottom, in the second half of the second note.
  local lo, hi = reach(roll, P.orange, 1.6 * ppb, 1.95 * ppb)
  eq(lo ~= nil, true, "the second note's line is drawn")
  eq(hi - lo >= 8, true, string.format("the vibrato shows: %.1f to %.1f", lo, hi))
  lo, hi = reach(roll, P.orange, 0.1 * ppb, 0.4 * ppb)
  eq(hi - lo < 1, true, "a note without one is level")
  local curve = ops_of(strips.curve)
  local lines = 0
  for _, op in ipairs(curve) do
    if op[1] == "p" and op[3] == P.green then lines = lines + 1 end
  end
  eq(lines >= 1, true, "the curve is a line in pixels")

  -- The pitch the engine sang, a line of its own.
  utau.pitch[clip.id] = { step = 5, ticks = {} }
  for tick = 0, 4 * require("utau.proto").TICKS, 5 do
    utau.pitch[clip.id].ticks[tick] = 6000 + 10 * math.sin(tick / 50)
  end
  T.after(function() utau.pitch[clip.id] = nil end)
  api.ui_snapshot(W, H)
  for _, s in ipairs(paw.ui.rects.surfaces or {}) do
    if s.key:find("^utau:roll#") then strips.roll = s end
  end
  roll = ops_of(strips.roll)
  lo = reach(roll, "#ffffff", 0, 4 * ppb)
  eq(lo ~= nil, true, "the sung pitch is drawn")

  -- The cursor moves: the same pictures.
  paw.keymap.feed("l")
  api.ui_snapshot(W, H)
  for _, s in ipairs(paw.ui.rects.surfaces or {}) do
    strips[s.key:match("^utau:(%a+)#")] = s
  end
  eq(paw.inspect(ops_of(strips.roll)) == paw.inspect(roll), true, "a cursor move changes nothing in the picture")

  -- Pictures off, or a terminal without them: the cells as before.
  utau.pitch[clip.id] = nil
  api.ui_caps_set({ graphics = false, cell = { w = 0, h = 0 } })
  -- A message running out between the two would differ.
  paw.ui.message = nil
  cells = api.ui_snapshot(W, H)
  api.ui_caps_set({ graphics = true, cell = { w = 10, h = 20 }, under = true })
  paw.opt.graphics = false
  local now = api.ui_snapshot(W, H)
  -- The editor's rows: the master's meter above may fall back meanwhile.
  local rect
  for _, r in ipairs(paw.ui.rects) do
    if r.name == "utau" then rect = r end
  end
  for i = rect.y + 1, rect.y + rect.h do
    eq(now[i], cells[i], "graphics off draws the same cells, row " .. i)
  end
  eq(paw.ui.rects.surfaces, nil, "and keeps no strip")
  paw.opt.graphics = true

  -- Split: the editor is in one window at a time, its strips that window's.
  paw.commands.exec("vs")
  api.ui_snapshot(W, H)
  local rolls = {}
  for _, s in ipairs(paw.ui.rects.surfaces or {}) do
    if s.key:find("^utau:roll#") then rolls[#rolls + 1] = s end
  end
  eq(#rolls, 1, "one roll")
  eq(rolls[1].key, "utau:roll#" .. rolls[1].win, "under its window's key")
end)

test("utau: the pitch line in pixels meets each note's edges where its cells do", function()
  load()
  local strips = require("utau.strips")
  -- Three cells a beat: a note from beat 0.35 is drawn from cell 1 (1.05
  -- rounds down), not 10.5 pixels in; one ending at 1.35 ends at cell 4.
  local list = { { pitch = 60, start = 0.35, length = 1 }, { pitch = 62, start = 2, length = 0.5 } }
  local x_at, beat_at = strips.warp(list, 0, 3, 10)
  eq(x_at(0.35), 10, "the note's start, on its cell's edge")
  eq(x_at(1.35), 40, "its end too")
  eq(x_at(2), 60, "the next note's start")
  eq(math.abs(beat_at(x_at(1.7)) - 1.7) < 1e-9, true, "and back")
  local ops = paw.canvas.draw(
    function(g, px)
      strips.roll(g, px, { list = list, clip = { start = 0, length = 4 }, scroll = 0, zoom = 3, top = 72 })
    end,
    { w = 200, h = 400, cell = { w = 10, h = 20 } }
  )
  local left, right
  for _, op in ipairs(ops) do
    if op[1] == "p" and op[3] == require("paw.theme").palette.orange then
      for x in op[2]:gmatch("[ML] ([%d.-]+) [%d.-]+") do
        x = tonumber(x)
        if x < 50 then
          left, right = math.min(left or x, x), math.max(right or x, x)
        end
      end
    end
  end
  eq(left, 10, "the line starts on the note's first cell")
  eq(right, 40, "and ends on its last cell's edge")
end)

-- Curves that follow their clip ------------------------------------------------

local UNDER = { 4, 5, 6, 7, 7.9 }

test("utau: = puts the curve back over what it covers", function()
  local track, clip = sung()
  local editor = require("utau.editor").editor
  editor:edit(clip.id)
  paw.ui.focus("utau")
  keep_curve()
  editor.curve, editor.beat, editor.pitch = "dyn", 1, 62
  T.keys("=in")
  paw.flush()
  eq(curves(track, { 4, 5, 7 }), "4:-50/0 5:0/100 7:5/-100", "=in under the note at the cursor, that curve only")
  T.keys("==")
  paw.flush()
  eq(curves(track, { 4, 7 }), "4:0/0 7:0/-100", "== in the whole clip")
  paw.ui.hide("utau")
end)

test("utau: curves move with their clip, and undo puts both back", function()
  local track, clip = sung()
  local before = curves(track, UNDER)
  eq(before, "4:-50/0 5:-10/100 6:30/0 7:5/-100 7.9:-17.5/0", "the curves as drawn")
  clip.start = 12
  paw.flush()
  api.undo_checkpoint()
  eq(
    curves(track, { 12, 13, 14, 15, 15.9 }),
    before:gsub("(%d+%.?%d*):", function(b) return (tonumber(b) + 8) .. ":" end),
    "the curves are under the clip at its new place"
  )
  eq(curves(track, { 5, 6 }), "5:0/0 6:0/0", "and gone from where it was")
  paw.undo()
  paw.flush()
  eq(clip.start, 4, "undo moves the clip back")
  eq(curves(track, UNDER), before, "and its curves, in the same step")
  eq(curves(track, { 13, 14 }), "13:0/0 14:0/0", "leaving nothing behind")
  paw.redo()
  paw.flush()
  eq(curves(track, { 13, 14 }), "13:-10/100 14:30/0", "redo moves them again, once")
end)

test("utau: a clip moved earlier, over its own old place, keeps its curves", function()
  local track, clip = sung()
  local before = curves(track, UNDER)
  clip.start = 2
  paw.flush()
  eq(
    curves(track, { 2, 3, 4, 5, 5.9 }),
    before:gsub("(%d+%.?%d*):", function(b) return (tonumber(b) - 2) .. ":" end),
    "the curves moved two beats earlier"
  )
  eq(curves(track, { 9 }), "9:0/0", "and the curves after the old place are as they were")
end)

test("utau: curves go with a clip moved to another vocal track", function()
  local track, clip = sung()
  local before = curves(track, UNDER)
  local other = vocal("Harmony", { 48 }, 20)
  paw.flush()
  api.undo_checkpoint()
  -- As a drag in the window moves it.
  paw.frontend.act.move_clip(clip.id, 4, other.id)
  paw.flush()
  api.undo_checkpoint()
  eq(clip:get().track, other.id, "the clip is on the other track")
  eq(curves(other, UNDER), before, "with its curves")
  eq(curves(track, { 5, 6 }), "5:0/0 6:0/0", "which left the first track")
  paw.undo()
  paw.flush()
  eq(curves(track, UNDER), before, "undo brings them back to the first track")
  eq(curves(other, { 5, 6 }), "5:0/0 6:0/0", "and off the other")
end)

test("utau: a duplicated or copied clip takes a copy of the curves", function()
  local track, clip = sung()
  local before = curves(track, UNDER)
  paw.cursor.set_track(track)
  paw.cursor.set_beat(5)
  paw.cmd("clip.duplicate")
  paw.flush()
  api.undo_checkpoint()
  eq(#track:clips(), 2, "a copy after the clip")
  local shifted = before:gsub("(%d+%.?%d*):", function(b) return (tonumber(b) + 4) .. ":" end)
  eq(curves(track, { 8, 9, 10, 11, 11.9 }), shifted, "with the curves of the original")
  eq(curves(track, UNDER), before, "which keeps its own")
  -- A copy dropped with the pointer, onto another vocal track.
  local other = vocal("Double", { 48 }, 30)
  paw.flush()
  api.undo_checkpoint()
  local made = paw.frontend.act.move_clip(clip.id, 16, other.id, true)
  paw.flush()
  eq(api.clip_get(made).track, other.id, "the copy is on the other track")
  eq(
    curves(other, { 16, 17, 18, 19, 19.9 }),
    before:gsub("(%d+%.?%d*):", function(b) return (tonumber(b) + 12) .. ":" end),
    "and has the curves too"
  )
  paw.undo()
  paw.flush()
  eq(curves(other, { 17, 18 }), "17:0/0 18:0/0", "undo takes the copy's curves away with it")
end)

test("utau: splitting or trimming a clip leaves the curves in place", function()
  local track = sung()
  local before = curves(track, UNDER)
  paw.cursor.set_track(track)
  paw.cursor.set_beat(6)
  paw.cmd("clip.split")
  paw.flush()
  eq(#track:clips(), 2, "two clips")
  eq(curves(track, UNDER), before, "the curves did not move")
  -- Cutting the first beat away moves the clip's start but not its notes.
  paw.edit.arrange.clear(track.id, 4, 5)
  paw.flush()
  eq(track:clips()[1].start, 5, "the clip starts later")
  eq(curves(track, { 5, 6, 7 }), "5:-10/100 6:30/0 7:5/-100", "the curves under it stay")
end)

test("utau: deleting a clip takes its curves, and pasting it brings them back", function()
  local track = sung()
  local before = curves(track, UNDER)
  paw.cursor.set_track(track)
  paw.cursor.set_beat(4)
  local value = paw.edit.arrange.delete({ kind = "char", r0 = 1, r1 = 1, c0 = 4, c1 = 8 })
  paw.flush()
  api.undo_checkpoint()
  eq(#track:clips(), 0, "the clip is gone")
  eq(curves(track, { 5, 6 }), "5:0/0 6:0/0", "and its curves with it")
  paw.cursor.set_beat(16)
  paw.edit.arrange.paste(value, true)
  paw.flush()
  eq(
    curves(track, { 16, 17, 18, 19, 19.9 }),
    before:gsub("(%d+%.?%d*):", function(b) return (tonumber(b) + 12) .. ":" end),
    "pasting the clip elsewhere brings its curves"
  )
  paw.undo()
  paw.undo()
  paw.flush()
  eq(curves(track, UNDER), before, "undoing the paste and the delete puts all back")
  eq(#track:clips(), 1, "with the clip")
end)

-- Getting the work out ------------------------------------------------------------

--- A vocal clip with every kind of note property, and curves under it.
local function rich()
  T.fresh()
  load()
  local track, clip = vocal("Lead", { 57, 60, 64, 62 }, 2)
  utau.configure(track.id, { singer = SINGER })
  local notes = require("utau.notes")
  notes.change_props(clip.id, function(p, _, i)
    if i == 1 then p.tu = 15 end
    if i == 2 then p.vb = { 60, 175, 30, 10, 20, 0, 0, 0 } end
    if i == 3 then p.pp = { snap = true, pts = { { -40, 0, 2 }, { 20, 5, 2 }, { 80, 0, 2 } } } end
    if i == 4 then p.ex = { { "vel", 140, -1 } } end
    return true
  end)
  local device = utau.device_of(track.id)
  notes.stroke(track.id, device, "dyn", { { 2, -40 }, { 4, 20 }, { 6, 0 } })
  paw.flush()
  return track, clip
end

--- The notes of a clip as text: pitch, place, lyric and properties.
local function describe(clip)
  local out = {}
  for _, n in ipairs(clip:notes()) do
    local p = n.meta and n.meta.utau or {}
    local parts = { n.pitch, n.start, n.length, n.meta and n.meta.lyric or "" }
    if p.tu then parts[#parts + 1] = "tu" .. p.tu end
    if p.vb then parts[#parts + 1] = "vb" .. table.concat(p.vb, ",") end
    if p.ex then parts[#parts + 1] = "ex" .. p.ex[1][1] .. p.ex[1][2] end
    out[#out + 1] = table.concat(parts, "/")
  end
  return table.concat(out, " ")
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() end
  return f ~= nil
end

test("utau: a vocal track exported to .ustx imports back the same", function()
  local track, clip = rich()
  if not utau.engine.find() then return "skipped: paw-utau-engine not found (set PAW_UTAU_ENGINE)" end
  local export = require("utau.export")
  local desc = export.describe({ tracks = { track.id } })
  eq(#desc.tracks, 1, "one track described")
  eq(desc.tracks[1].singer, SINGER, "with its singer")
  eq(#desc.tracks[1].parts[1].notes, 4, "and its notes")
  local path = T.scratch .. "/out/song.ustx"
  local files = export.write(path, { tracks = { track.id } })
  eq(files[1], path, "the file written")
  eq(exists(path), true, "is there")
  local text = T.read_file(path)
  eq(text:find("ustx_version", 1, true) ~= nil, true, "an OpenUtau project: " .. text:sub(1, 200))
  local want = describe(clip)
  local ids = require("utau.import").file(path, { at = 0 })
  local back = paw.track(ids[1])
  local got = back:clips()[1]
  eq(got.start, clip.start, "the part where the clip was")
  -- OpenUtau decides how long a part is; it covers the notes.
  eq(got.length >= clip.length, true, "and as long, at least")
  eq(describe(got), want, "the same notes, lyrics and properties")
  local pp = got:notes()[3].meta.utau.pp
  eq(#pp.pts .. "/" .. pp.pts[2][1] .. "/" .. pp.pts[2][2], "3/20/5", "and pitch points")
  eq(utau.config(back.id).singer, SINGER, "the singer")
  local notes = require("utau.notes")
  for _, b in ipairs({ 2, 3, 4, 5 }) do
    near(
      notes.curve_at(back.id, utau.device_of(back.id), "dyn", b),
      notes.curve_at(track.id, utau.device_of(track.id), "dyn", b),
      1,
      "dynamics at beat " .. b
    )
  end
end)

test("utau: a clip exports to UTAU's .ust and to MIDI with lyrics", function()
  local track, clip = rich()
  if not utau.engine.find() then return "skipped: paw-utau-engine not found (set PAW_UTAU_ENGINE)" end
  local export = require("utau.export")
  local function plain(c)
    -- MIDI has no parts: the notes come back where they were in the song.
    local out, first = {}, c:notes()[1].start
    for _, n in ipairs(c:notes()) do
      out[#out + 1] = n.pitch .. "/" .. (n.start - first) .. "/" .. n.length .. "/" .. (n.meta and n.meta.lyric or "")
    end
    return table.concat(out, " ")
  end
  local want = plain(clip)
  for _, ext in ipairs({ "ust", "mid" }) do
    local path = T.scratch .. "/out/clip." .. ext
    local files = export.write(path, { clip = clip.id })
    eq(#files, 1, ext .. ": one file")
    local ids = require("utau.import").file(path, { at = 0 })
    local back = paw.track(ids[#ids]):clips()[1]
    eq(plain(back), want, ext .. ": the same notes and lyrics")
  end
  -- Through the command, on the clip under the cursor.
  paw.cursor.set_track(track)
  paw.cursor.set_beat(3)
  paw.cmd("utau.export", { T.scratch .. "/out/cmd.ustx", clip = true })
  eq(exists(T.scratch .. "/out/cmd.ustx"), true, "utau.export writes the file")
end)

test("utau: opening in OpenUtau writes a .ustx beside the project and says what it would run", function()
  local track = rich()
  if not utau.engine.find() then return "skipped: paw-utau-engine not found (set PAW_UTAU_ENGINE)" end
  local export = require("utau.export")
  os.execute("mkdir -p '" .. T.scratch .. "/proj'")
  paw.project.save(T.scratch .. "/proj/song.json")
  eq(export.open_path(), T.scratch .. "/proj/song.ustx", "beside the project, named after it")
  paw.opt.utau_openutau = ""
  local path, argv = export.open({ dry = true })
  eq(exists(path), true, "the file is written")
  eq(argv[#argv], path, "and OpenUtau is to be started on it")
  eq(argv[1], os.getenv("PAW_UTAU_OPENUTAU") or "OpenUtau", "as the extension starts it")
  paw.opt.utau_openutau = "env FOO=1 OpenUtau"
  eq(table.concat(export.open_command("/x.ustx"), " "), "env FOO=1 OpenUtau /x.ustx", "a command of one's own")
  paw.opt.utau_openutau = ""
  eq(track ~= nil, true, "")
end)

-- Freezing ----------------------------------------------------------------------------

--- The left channel of a 16-bit render as numbers.
local function samples(info)
  local data = T.read_file(info.path)
  local at = data:find("data", 1, true) + 8
  local out = {}
  for i = at, #data - 3, 4 do
    local lo, hi = data:byte(i, i + 1)
    local v = lo + hi * 256
    out[#out + 1] = (v >= 32768 and v - 65536 or v) / 32768
  end
  return out
end

test("utau: a frozen track plays the same audio as the sung one, and unfreezes", function()
  T.fresh()
  local why = need_singer()
  if why then return why end
  paw.project.tempo = 120
  local track = vocal("Lead", { 57, 60, 64 }, 0)
  utau.configure(track.id, { singer = SINGER })
  local sung = T.render({ bits = 16, tail = 0, ["end"] = 4 })
  local before = #paw.tracks()
  paw.cursor.set_track(track)
  paw.cmd("utau.freeze")
  eq(utau.frozen(track.id), true, "the track is frozen")
  eq(#paw.tracks(), before + 1, "with an audio track")
  local audio = paw.tracks()[before + 1]
  eq(audio.name, "Lead (frozen)", "named after it, right below it")
  eq(audio:clips()[1].kind, "audio", "holding audio")
  eq(track.mute, true, "the vocal track is muted")
  eq(utau.status(track.id), "frozen", "and the engine leaves it")
  local found = false
  for _, t in ipairs(utau.snapshot().tracks) do
    found = found or t.id == tostring(track.id)
  end
  eq(found, false, "it is not sent to the engine")
  local frozen = T.render({ bits = 16, tail = 0, ["end"] = 4 })
  local a, b = samples(sung), samples(frozen)
  eq(#a, #b, "renders of one length")
  local diff, energy = 0, 0
  for i = 1, #a do
    diff = math.max(diff, math.abs(a[i] - b[i]))
    energy = math.max(energy, math.abs(a[i]))
  end
  eq(energy > 0.05, true, "the sung track sounds")
  eq(diff < 0.002, true, "the frozen track sounds the same (largest difference " .. diff .. ")")
  paw.cmd("utau.unfreeze")
  eq(utau.frozen(track.id), false, "unfrozen")
  eq(#paw.tracks(), before, "the audio track is gone")
  eq(track.mute, false, "the vocal track sounds again")
  local again = T.render({ bits = 16, tail = 0, ["end"] = 4 })
  eq(T.read_file(again.path) == T.read_file(sung.path), true, "and sings as it did")
end)

-- Singer presets -----------------------------------------------------------------------

test("utau: a track's voice is saved as a singer preset and given to another track", function()
  T.fresh()
  load()
  paw.opt.utau_presets_dir = T.scratch .. "/presets"
  local a = vocal("Lead")
  local b = vocal("Harmony")
  utau.configure(a.id, {
    singer = "Someone",
    phonemizer = "Some.Phonemizer",
    renderer = "CLASSIC",
    resampler = "moresampler",
    voice_color = "soft",
    options = { pitchmode = "manual", unison = "3" },
  })
  local device = utau.device_of(a.id)
  api.device_set_param(device, "brec", 30)
  api.device_set_param(device, "genc", -10)
  utau.configure(b.id, { singer = "Other", options = { keyshift = "12" } })
  api.device_set_param(utau.device_of(b.id), "tenc", 50)
  paw.cursor.set_track(a)
  paw.cmd("utau.singer_save", { "Soft", "lead" })
  local path = T.scratch .. "/presets/Soft lead.json"
  eq(exists(path), true, "the preset is a file in the presets folder")
  local text = T.read_file(path)
  eq(text:find('"singer": "Someone"', 1, true) ~= nil, true, "JSON, as the engine reads it")
  eq(#require("utau.singer_presets").list(), 1, "listed")
  paw.flush()
  api.undo_checkpoint()
  paw.cursor.set_track(b)
  paw.cmd("utau.singer_preset", { "soft" })
  local c = utau.config(b.id)
  eq(
    table.concat({ c.singer, c.phonemizer, c.renderer, c.resampler, c.voice_color }, " "),
    "Someone Some.Phonemizer CLASSIC moresampler soft",
    "the other track has the whole voice"
  )
  eq(
    c.options.pitchmode .. "/" .. c.options.unison .. "/" .. tostring(c.options.keyshift),
    "manual/3/nil",
    "with the preset's options and none of its own"
  )
  local params = api.device_get(utau.device_of(b.id)).params
  eq(params.brec .. "/" .. params.genc .. "/" .. params.tenc, "30/-10/0", "and the values its curves hold")
  paw.undo()
  eq(utau.config(b.id).singer, "Other", "one undo puts the old voice back")
  paw.cmd("utau.singer_delete", { "Soft", "lead" })
  eq(exists(path), false, "a preset is deleted")
  paw.opt.utau_presets_dir = ""
end)

-- Installing singers ------------------------------------------------------------------

--- A zip file (stored, not compressed) of `files` = { { name, data } }.
local function zip(path, files)
  local crc_table = {}
  for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
      if c % 2 == 1 then
        c = bit.bxor(bit.rshift(c, 1), 0xEDB88320)
      else
        c = bit.rshift(c, 1)
      end
    end
    crc_table[i] = c
  end
  local function crc32(s)
    local c = 0xFFFFFFFF
    for i = 1, #s do
      c = bit.bxor(crc_table[bit.band(bit.bxor(c, s:byte(i)), 0xFF)], bit.rshift(c, 8))
    end
    c = bit.bxor(c, 0xFFFFFFFF)
    return c < 0 and c + 4294967296 or c
  end
  local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
  local function u32(v) return u16(v % 65536) .. u16(math.floor(v / 65536) % 65536) end
  local body, central, offset = {}, {}, 0
  for _, f in ipairs(files) do
    local name, data = f[1], f[2]
    local crc = crc32(data)
    local head = "PK\3\4"
      .. u16(20)
      .. u16(0x0800)
      .. u16(0)
      .. u16(0)
      .. u16(0x21)
      .. u32(crc)
      .. u32(#data)
      .. u32(#data)
      .. u16(#name)
      .. u16(0)
      .. name
    body[#body + 1] = head .. data
    central[#central + 1] = "PK\1\2"
      .. u16(20)
      .. u16(20)
      .. u16(0x0800)
      .. u16(0)
      .. u16(0)
      .. u16(0x21)
      .. u32(crc)
      .. u32(#data)
      .. u32(#data)
      .. u16(#name)
      .. u16(0)
      .. u16(0)
      .. u16(0)
      .. u16(0)
      .. u32(0)
      .. u32(offset)
      .. name
    offset = offset + #head + #data
  end
  local cd = table.concat(central)
  T.write_file(
    path,
    table.concat(body)
      .. cd
      .. "PK\5\6"
      .. u16(0)
      .. u16(0)
      .. u16(#files)
      .. u16(#files)
      .. u32(#cd)
      .. u32(offset)
      .. u16(0)
  )
end

test("utau: singers install from an archive or a folder, and are listed", function()
  T.fresh()
  load()
  local to = T.scratch .. "/openutau"
  local install = require("utau.install")
  eq(#install.installed({ to = to }), 0, "nothing installed yet")
  -- A folder.
  local folder = T.scratch .. "/Tiny Folder Bank"
  os.execute("mkdir -p '" .. folder .. "'")
  T.write_file(folder .. "/character.txt", "name=Tiny Folder\n")
  T.write_file(folder .. "/oto.ini", "a.wav=- a,0,100,-200,50,20\n")
  local got = install.install(folder, { to = to })
  eq(got[1].path, to .. "/Singers/Tiny Folder Bank", "a folder is copied into Singers")
  eq(exists(to .. "/Singers/Tiny Folder Bank/oto.ini"), true, "with its files")
  fails(function() install.install(folder, { to = to }) end, "installed already", "a second time")
  -- An archive, by the engine.
  if not utau.engine.find() then return "skipped (archives): paw-utau-engine not found (set PAW_UTAU_ENGINE)" end
  local archive = T.scratch .. "/tiny.zip"
  zip(archive, {
    { "Tiny Zip Bank/character.txt", "name=Tiny Zip\n" },
    { "Tiny Zip Bank/oto.ini", "a.wav=- a,0,100,-200,50,20\n" },
  })
  got = install.install(archive, { to = to })
  eq(#got, 1, "the engine reports what it installed")
  eq(got[1].kind .. " " .. got[1].path, "classic " .. to .. "/Singers/Tiny Zip Bank", "a classic voicebank in Singers")
  eq(exists(to .. "/Singers/Tiny Zip Bank/oto.ini"), true, "unpacked")
  local names = {}
  for _, s in ipairs(install.installed({ to = to })) do
    names[#names + 1] = s.name .. ":" .. s.type
  end
  eq(table.concat(names, " "), "Tiny Folder:classic Tiny Zip:classic", "both are listed")
  fails(function() install.install(T.scratch .. "/nothing.zip", { to = to }) end, "no such file", "a missing file")
end)

-- Harmony and doubling -----------------------------------------------------------------

test("utau: a harmony track sings the melody a diatonic interval away in the key", function()
  T.fresh()
  load()
  local h = require("utau.harmony")
  -- C major: C D E F G -> E F G A B a third above.
  eq(h.transpose(60, 2, h.parse_key("C")), 64, "C up a third is E")
  eq(h.transpose(62, 2, h.parse_key("C")), 65, "D up a third is F (a minor third)")
  eq(h.transpose(71, 2, h.parse_key("C")), 74, "B up a third is D, over the octave")
  eq(h.transpose(61, 2, h.parse_key("C")), 65, "C# keeps its distance from C")
  eq(h.transpose(69, -2, h.parse_key("A minor")), 65, "A down a third in A minor is F")
  eq(
    h.key_name(h.detect_key({ { 62, 1 }, { 64, 1 }, { 66, 1 }, { 67, 1 }, { 69, 2 }, { 71, 1 }, { 73, 1 }, { 74, 2 } })),
    "D major",
    "a D major scale is in D major"
  )
  local track, clip = vocal("Lead", { 60, 62, 64, 65, 67 }, 0)
  require("utau.notes").set_lyric(clip.id, 3, "ら")
  require("utau.notes").stroke(track.id, utau.device_of(track.id), "dyn", { { 1, -30 }, { 3, 10 } })
  utau.configure(track.id, { singer = "Someone" })
  paw.flush()
  paw.cursor.set_track(track)
  paw.cmd("utau.harmony", { "3up" })
  local made = paw.cursor.track()
  eq(made.name, "Lead (third above)", "a new track, named for the interval")
  eq(api.track_list()[2], made.id, "right under the lead")
  local pitches = {}
  for _, n in ipairs(made:clips()[1]:notes()) do
    pitches[#pitches + 1] = n.pitch
  end
  eq(table.concat(pitches, " "), "64 65 67 69 71", "the notes a third up in C major")
  eq(made:clips()[1]:notes()[3].meta.lyric, "ら", "with the lyrics")
  eq(utau.config(made.id).singer, "Someone", "the voice")
  near(curve(made, "dyn", 2), curve(track, "dyn", 2), 1e-6, "and the curves")
  near(made.volume, track.volume - 3, 1e-6, "a little quieter")
  -- The project's key wins over the melody's.
  paw.harmony.set_key("A minor")
  paw.flush()
  api.undo_checkpoint()
  local _, info = h.create(track.id, { interval = "3down" })
  eq(h.key_name(info.key) .. " " .. info.key_source, "A minor project", "the project's key is used")
  paw.undo()
  eq(#paw.tracks(), 2, "one undo removes a harmony track")
end)

test("utau: a double sings the same notes, a little apart in timing and tuning", function()
  T.fresh()
  load()
  local track, clip = vocal("Lead", { 60, 62, 64, 65, 67, 69 }, 0)
  paw.flush()
  paw.cursor.set_track(track)
  paw.cmd("utau.double")
  local made = paw.cursor.track()
  eq(made.name, "Lead (double)", "a double")
  local moved, tuned, same = 0, 0, true
  for i, n in ipairs(made:clips()[1]:notes()) do
    local src = clip:notes()[i]
    same = same and n.pitch == src.pitch and n.start == src.start
    local p = n.meta.utau or {}
    if p.tu then
      tuned = tuned + 1
      eq(math.abs(p.tu) <= 8, true, "tuning within 8 cents")
    end
    if p.ph and p.ph[1].index == 0 and p.ph[1].offset then
      moved = moved + 1
      eq(math.abs(p.ph[1].offset) <= 18, true, "onset within 18 ticks")
    end
  end
  eq(same, true, "the same notes")
  eq(moved > 0 and tuned > 0, true, "some notes start a little apart, some are tuned a little apart")
  local first = made:clips()[1]:notes()[1].meta.utau
  paw.cursor.set_track(track)
  paw.cmd("utau.double")
  local again = paw.cursor.track():clips()[1]:notes()[1].meta.utau
  eq(paw.inspect(again), paw.inspect(first), "a double of the same take is the same")
end)

-- What depends on the renderer ------------------------------------------------------------

--- Stand in for the engine: what is sent is kept, decoded, instead of sent.
local function stand_in()
  local proto = require("utau.proto")
  local mp = require("utau.msgpack")
  local sent = {}
  local real_send, real_connected = utau.engine.send, utau.engine.connected
  utau.engine.send = function(frame)
    for _, f in ipairs((proto.split(frame))) do
      sent[#sent + 1] = { name = proto.name[f.type], body = mp.decode(f.body, 1) }
    end
    return true
  end
  utau.engine.connected = function() return true end
  local function restore()
    utau.engine.send, utau.engine.connected = real_send, real_connected
  end
  return sent, restore
end

test("utau: AI pitch, takes and the renderer's curves send what the protocol says", function()
  T.fresh()
  load()
  local proto = require("utau.proto")
  local mp = require("utau.msgpack")
  local r = require("utau.renderer")
  local track, clip = vocal("Lead", { 60, 62, 64 }, 0)
  paw.flush()
  local sent, restore = stand_in()
  local ok, err = pcall(function()
    paw.cursor.set_track(track)
    paw.cursor.set_beat(0)
    -- AI pitch is a track option the engine reads.
    paw.cmd("utau.ai_pitch", { "off" })
    eq(utau.config(track.id).options.pitchmode, "manual", "off is pitchmode=manual")
    paw.cmd("utau.ai_pitch", { "on" })
    eq(utau.config(track.id).options, nil, "on is the engine's default")
    -- A retake is RunBatchEdit "retake" for the clip's part.
    local id = r.retake(clip.id, "new", { kind = "timbre", notes = { [2] = true } })
    local m = sent[#sent]
    eq(m.name, "RunBatchEdit", "a batch edit is sent")
    eq(
      m.body[1] .. " " .. m.body[2] .. " " .. m.body[3][1] .. " " .. m.body[4][1],
      id .. " retake " .. clip.id .. " 2",
      "request, name, part and note"
    )
    local args = require("utau.json").decode(m.body[5])
    eq(args.action .. " " .. args.kind .. " " .. args.notes[1], "new timbre 2", "and the arguments the engine reads")
    -- The answer, as the engine frames it.
    local answer =
      '{"error":null,"changed":1,"phrases":[{"hash":"77","start":0,"current":1,"count":2,"vcurrent":0,"vcount":1,"notes":[1,2,3]}]}'
    local frame = proto.frame(
      proto.type.BatchEditResult,
      mp.array(5) .. mp.uint(id) .. mp.bool(true) .. mp.str(answer) .. mp.array(0) .. mp.array(0)
    )
    local f = proto.split(frame)[1]
    utau.engine.handlers.BatchEditResult(proto.message(f), f)
    eq(r.take_info(clip.id, 2).current .. "/" .. r.take_info(clip.id, 2).count, "1/2", "the take each note is on")
    eq(r.last.changed, 1, "and how many phrases changed")
    for _, action in ipairs({ "prev", "next", "info" }) do
      r.retake(clip.id, action)
      eq(require("utau.json").decode(sent[#sent].body[5]).action, action, action .. " is sent")
    end
    -- A curve of the renderer's own, drawn on a slot of the device.
    utau.renderers = {
      renderers = {
        {
          id = "DIFFSINGER",
          name = "DIFFSINGER",
          singer_types = { "diffsinger" },
          expressions = {
            { abbr = "dyn", name = "dynamics", min = -240, max = 120, default = 0, kind = 1 },
            { abbr = "ene", name = "energy", min = -100, max = 100, default = 0, kind = 1 },
            { abbr = "spk1", name = "voice colour 1", min = 0, max = 100, default = 100, kind = 1 },
          },
        },
      },
      resamplers = {},
      wavtools = {},
    }
    utau.configure(track.id, { renderer = "DIFFSINGER" })
    local names = {}
    for _, e in ipairs(r.extra_expressions(track.id)) do
      names[#names + 1] = e.abbr
    end
    eq(table.concat(names, " "), "ene spk1", "the renderer's own curves are offered")
    keep_curve()
    paw.cmd("utau.curve", { "ene" })
    paw.cmd("utau.curve", { "spk1" })
    eq(r.slot_of(track.id, "ene") .. " " .. r.slot_of(track.id, "spk1"), "x1 x2", "each on a slot")
    eq(api.device_get(utau.device_of(track.id)).params.x2, 100, "starting at the curve's default")
    require("utau.notes").stroke(track.id, utau.device_of(track.id), "x1", { { 0, 40 }, { 2, -20 } })
    paw.flush()
    local part = utau.snapshot().parts[1]
    local by = {}
    for _, c in ipairs(part.curves) do
      by[c.abbr] = c
    end
    eq(by.ene ~= nil and by.ene.knots[1][2], 40, "the engine gets the curve by its own name, in its units")
    eq(by.spk1 ~= nil and #by.spk1.knots, 0, "an untouched curve is at its default")
    -- Unison and shifts are options too.
    paw.cmd("utau.unison", { 4, spacing = 50 })
    paw.cmd("utau.shift", { 12, cents = -20 })
    local o = utau.config(track.id).options
    eq(
      o.unison .. " " .. o.unison_spacing .. " " .. o.keyshift .. " " .. o.pitchshift,
      "4 50 12 -20",
      "unison and shift options"
    )
    local snap = utau.snapshot()
    local opts = snap.tracks[1].config.options
    eq(opts.unison .. " " .. opts.keyshift, "4 12", "and the engine is given them")
  end)
  restore()
  if not ok then error(err, 0) end
end)

test("utau: a timing take moves note onsets, and take 0 puts them back", function()
  T.fresh()
  load()
  local r = require("utau.renderer")
  local track, clip = vocal("Lead", { 60, 62, 64, 65, 67, 69, 71, 72 }, 0)
  paw.flush()
  local n = r.timing(clip.id, 1)
  eq(n > 0, true, "notes moved")
  local offsets = {}
  for _, note in ipairs(clip:notes()) do
    local ph = note.meta.utau and note.meta.utau.ph
    offsets[#offsets + 1] = ph and ph[1].offset or 0
  end
  for _, o in ipairs(offsets) do
    eq(math.abs(o) <= r.TIMING_RANGE, true, "within the range")
  end
  r.timing(clip.id, 1)
  local same = {}
  for _, note in ipairs(clip:notes()) do
    local ph = note.meta.utau and note.meta.utau.ph
    same[#same + 1] = ph and ph[1].offset or 0
  end
  eq(table.concat(same, " "), table.concat(offsets, " "), "the same take is the same")
  r.timing(clip.id, 0)
  for _, note in ipairs(clip:notes()) do
    eq(note.meta.utau and note.meta.utau.ph, nil, "take 0 takes the offsets away")
  end
  eq(track ~= nil, true, "")
end)

-- Step input in the vocal editor (utau.step) -----------------------------------------

--- A vocal track with an empty clip open in the editor, and a controller on a test port.
local function stepping()
  T.fresh()
  load()
  api.midi_test_ports({ "Test Keys" })
  paw.opt.note_grid = 0.25
  local track = paw.add_track({ name = "Vocal" })
  track:add_device(utau.DEVICE)
  local clip = track:add_clip({ start = 0, length = 8 })
  paw.flush()
  api.undo_checkpoint()
  paw.cursor.set_track(track)
  paw.cursor.set_beat(0)
  paw.cmd("clip.edit")
  local editor = require("utau.editor").editor
  editor.beat, editor.pitch = 0, 60
  return editor, clip
end

local function hold(pitch) paw.midi.inject({ type = "note_on", pitch = pitch, velocity = 100, port = "Test Keys" }) end
local function let_go(pitch) paw.midi.inject({ type = "note_off", pitch = pitch, port = "Test Keys" }) end
local function strike(pitch)
  hold(pitch)
  let_go(pitch)
  paw.flush()
end

local function stepping_test(name, fn)
  test(name, function()
    local ok, err = xpcall(fn, debug.traceback)
    paw.keymap.set_mode("n")
    api.midi_test_ports({})
    if not ok then error(err, 0) end
  end)
end

stepping_test(
  "utau step input: I, then keys one after the other add notes, and Esc with u takes them all back",
  function()
    local editor, clip = stepping()
    T.keys("I")
    eq(paw.step.active(), "utau", "the vocal editor listens")
    strike(60)
    strike(64)
    local list = clip:notes()
    eq(#list, 2, "two notes")
    eq(list[1].pitch .. "@" .. list[1].start .. "+" .. list[1].length, "60@0+0.5", "a step long: two steps of the grid")
    eq(list[2].pitch .. "@" .. list[2].start, "64@0.5", "the second after the first")
    eq(list[1].meta == nil or list[1].meta.lyric == nil, true, "with the default lyric")
    eq(editor.beat, 1, "the cursor is at the end of the second")
    T.keys("<Esc>")
    T.keys("u")
    eq(#clip:notes(), 0, "u takes back every note of the insert")
  end
)

stepping_test("utau step input: a chord enters its highest note, and paw says so once", function()
  local editor, clip = stepping()
  local said = {}
  local notify = paw.notify
  paw.notify = function(text, ...)
    said[#said + 1] = text
    return notify(text, ...)
  end
  local ok, err = pcall(function()
    T.keys("I")
    hold(60)
    hold(67)
    let_go(60)
    let_go(67)
    paw.flush()
    hold(62)
    hold(65)
    let_go(62)
    let_go(65)
    paw.flush()
  end)
  paw.notify = notify
  if not ok then error(err, 0) end
  local list = clip:notes()
  eq(#list, 2, "a note for each chord")
  eq(list[1].pitch .. "," .. list[2].pitch, "67,65", "the highest of each")
  local count = 0
  for _, text in ipairs(said) do
    if text:find("one note at a time", 1, true) then count = count + 1 end
  end
  eq(count, 1, "the message comes once")
  eq(editor.beat, 1, "the cursor stepped on twice")
end)

stepping_test("utau step input: <Space> rests one step and adds nothing", function()
  local editor, clip = stepping()
  T.keys("I")
  T.keys("<Space>")
  eq(editor.beat, 0.5, "one step on")
  eq(#clip:notes(), 0, "no note")
  strike(60)
  eq(clip:notes()[1].start, 0.5, "the next note starts after the rest")
  T.keys("<BS>")
  eq(#clip:notes(), 0, "<BS> takes the last note back")
  eq(editor.beat, 0.5, "and the cursor")
end)
