-- Media files and rendering: formats a render can write, media paths kept
-- relative to the project, relinking what went missing.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local paw = require("paw")
local api = paw.api

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() end
  return f ~= nil
end

test("a render to a format that cannot be written is refused before rendering", function()
  fresh()
  T.tone("Synth", 2)
  local heard = false
  local off = paw.on("render.before", function() heard = true end)
  local path = T.scratch .. "/refused.m4a"
  T.fails(function() paw.render(path, { tail = 0 }) end, "AAC", "an AAC render")
  T.fails(function() paw.render(path, { tail = 0 }) end, "%.wav", "the message names what can be written")
  T.fails(function() paw.render(T.scratch .. "/refused.xyz", { tail = 0 }) end, "xyz", "an unknown extension")
  eq(exists(path), false, "no file is written")
  eq(heard, false, "nothing is rendered, not even what renders before")
  paw.off(off)
  T.fails(function() paw.cmd("render", { path }) end, "AAC", "the command refuses it too")
  eq(exists(path), false, "and writes nothing")
  local names = {}
  for _, f in ipairs(api.render_formats()) do names[#names + 1] = f.name end
  eq(names[1], "WAV", "the formats that can be written are listed")
end)

--- A file of `seconds` of a steady level, at 48 kHz.
local function steady(path, seconds, level)
  local s = {}
  for i = 1, math.floor(seconds * 48000) do s[i] = level end
  return T.write_wav(path, s)
end

local function mkdir(path) os.execute("mkdir -p '" .. path .. "'") end

local function peak()
  return T.render({ tail = 0, bits = 16 }).peak
end

local function missing_warnings()
  local n = 0
  for _, w in ipairs(api.warnings()) do
    if w:find("missing", 1, true) then n = n + 1 end
  end
  return n
end

--- A project in `dir` playing `media/a.wav` from inside its folder and
--- `outside` from elsewhere.
local function project_in(dir, outside)
  fresh()
  mkdir(dir .. "/media")
  local t = paw.add_track({ name = "inside" })
  t:add_clip({ file = steady(dir .. "/media/a.wav", 1, 0.25), start = 0, length = 2 })
  if outside then
    local u = paw.add_track({ name = "outside" })
    u:add_clip({ file = outside, start = 0, length = 2 })
  end
  paw.project.save(dir .. "/song.json")
  return t
end

test("a project folder that is moved opens with every file", function()
  local root = T.scratch .. "/moved"
  mkdir(root)
  local outside = steady(root .. "/elsewhere.wav", 1, 0.5)
  project_in(root .. "/one", outside)
  local text = T.read_file(root .. "/one/song.json")
  eq(text:find('"media/a.wav"', 1, true) ~= nil, true, "a file inside the folder is saved relative to it")
  eq(text:find(outside, 1, true) ~= nil, true, "one outside it by its full path")
  os.rename(root .. "/one", root .. "/two")
  api.warnings()
  paw.project.load(root .. "/two/song.json")
  eq(missing_warnings(), 0, "nothing is missing")
  local clip = paw.tracks()[1]:clips()[1]
  eq(clip.file, root .. "/two/media/a.wav", "the clip plays the file in the folder's new place")
  eq(clip.offline, nil, "and is not offline")
  T.near(peak(), 0.75, 0.002, "both files play")
  eq(paw.project.modified, false, "and opening it changes nothing")
end)

test("an old project with full paths opens unchanged", function()
  local dir = T.scratch .. "/old"
  project_in(dir)
  local text = T.read_file(dir .. "/song.json")
  local absolute = dir .. "/media/a.wav"
  T.write_file(dir .. "/old.json", (text:gsub('"media/a.wav"', '"' .. absolute .. '"')))
  paw.project.load(dir .. "/old.json")
  eq(paw.tracks()[1]:clips()[1].file, absolute, "the path is as it was")
  T.near(peak(), 0.25, 0.002, "and it plays")
  -- Moved with the old full path in it: found by its place in the folder.
  os.rename(dir, dir .. "-moved")
  paw.project.load(dir .. "-moved/old.json")
  eq(paw.tracks()[1]:clips()[1].file, dir .. "-moved/media/a.wav", "a full path into the old folder is found in the new one")
  T.near(peak(), 0.25, 0.002, "and plays")
end)

test("a renamed file is offline, reported once, kept on saving, and relinked", function()
  local dir = T.scratch .. "/renamed"
  project_in(dir)
  T.tone("synth", 2)
  paw.project.save()
  os.rename(dir .. "/media/a.wav", dir .. "/media/b.wav")
  api.warnings()
  paw.project.load(dir .. "/song.json")
  eq(missing_warnings(), 1, "the missing file is reported once")
  local clip = paw.tracks()[1]:clips()[1]
  eq(clip.offline, true, "its clip is offline")
  eq(#paw.media.missing(), 1, "and listed as missing")
  local state = paw.frontend.state(-1)
  local drawn
  for _, c in ipairs(state.clips) do if c.id == clip.id then drawn = c end end
  eq(drawn.offline, true, "the window is told")
  eq(drawn.name:find("offline", 1, true) ~= nil, true, "and draws it as offline")
  paw.flush()
  eq(missing_warnings(), 0, "playing the project does not warn again")
  paw.project.save()
  eq(T.read_file(dir .. "/song.json"):find('"media/a.wav"', 1, true) ~= nil, true, "saving keeps the original path")

  local result = paw.media.relink(dir .. "/media/a.wav", dir .. "/media/b.wav")
  eq(result.clips, 1, "one clip is relinked")
  clip = paw.tracks()[1]:clips()[1]
  eq(clip.offline, nil, "it is online")
  T.near(T.channel_peaks(T.render({ tail = 0, bits = 16, tracks = { paw.tracks()[1].id } })), 0.25, 0.002, "and plays")
  api.undo_checkpoint()
  paw.undo()
  eq(paw.tracks()[1]:clips()[1].offline, true, "undo puts the old path back")
  paw.redo()
  paw.project.save()
  eq(T.read_file(dir .. "/song.json"):find('"media/b.wav"', 1, true) ~= nil, true, "the new path is saved")
end)

test("a missing file is found by name in the project's folder and beside others found", function()
  local dir = T.scratch .. "/byname"
  project_in(dir)
  local u = paw.add_track()
  u:add_clip({ file = steady(dir .. "/media/c.wav", 1, 0.5), start = 0, length = 2 })
  paw.project.save()
  mkdir(dir .. "/deep/er")
  os.rename(dir .. "/media/a.wav", dir .. "/deep/er/a.wav")
  os.rename(dir .. "/media/c.wav", dir .. "/deep/er/c.wav")
  api.warnings()
  paw.project.load(dir .. "/song.json")
  eq(missing_warnings(), 0, "nothing is reported missing")
  eq(paw.tracks()[1]:clips()[1].file, dir .. "/deep/er/a.wav", "found where it went")
  eq(paw.project.modified, true, "the project is modified, so that saving keeps the new place")
  T.near(peak(), 0.75, 0.002, "both play")

  -- Elsewhere altogether: a directory to search.
  local away = T.scratch .. "/byname-away"
  mkdir(away .. "/sub")
  paw.project.save()
  os.rename(dir .. "/deep/er/a.wav", away .. "/sub/a.wav")
  paw.project.load(dir .. "/song.json")
  eq(#paw.media.missing(), 1, "one is missing")
  local result = paw.media.search(away)
  eq(result.found, 1, "a directory search finds it")
  eq(#paw.media.missing(), 0, "and nothing is missing")
end)

test("collecting copies outside files into the project's media folder", function()
  local dir = T.scratch .. "/collect"
  mkdir(T.scratch .. "/loose")
  local outside = steady(T.scratch .. "/loose/x.wav", 1, 0.5)
  project_in(dir, outside)
  -- The same bytes as the project's own media/a.wav, from elsewhere.
  local twin = steady(T.scratch .. "/loose/twin.wav", 1, 0.25)
  paw.add_track({ name = "twin" }):add_clip({ file = twin, start = 4, length = 2 })
  api.undo_checkpoint()
  local result = paw.media.collect()
  eq(result.copied, 1, "the one outside file is copied")
  eq(paw.tracks()[2]:clips()[1].file, dir .. "/media/x.wav", "its clip plays the copy")
  eq(result.same, 1, "a file with the bytes of one in the folder is not copied")
  eq(paw.tracks()[3]:clips()[1].file, dir .. "/media/a.wav", "its clip plays that one")
  eq(T.read_file(outside) ~= nil, true, "the original stays")
  T.near(peak(), 0.75, 0.002, "and everything plays")
  api.undo_checkpoint()
  paw.undo()
  eq(paw.tracks()[2]:clips()[1].file, outside, "one undo step")
  paw.redo()

  paw.opt.copy_imports = true
  local clip = paw.import_audio(steady(T.scratch .. "/loose/y.wav", 1, 0.5), { start = 0 })
  paw.opt.copy_imports = false
  eq(clip.file, dir .. "/media/y.wav", "with copy_imports, importing copies too")
end)

test("a project folder records the hash of each file in media.json, the same on each save", function()
  local dir = T.scratch .. "/hashes"
  project_in(dir)
  paw.project.save(dir)
  local first = T.read_file(dir .. "/media.json")
  local hash = paw.media.list()[1].hash
  eq(hash and hash:match("^b3:%x+$") ~= nil and #hash == 67, true, "paw.media.list gives the hash")
  eq(first:find('"media/a.wav"', 1, true) ~= nil and first:find(hash, 1, true) ~= nil, true,
    "media.json names the file as the clip does, with its hash")
  paw.project.load(dir)
  paw.project.save()
  eq(T.read_file(dir .. "/media.json"), first, "saved again, the same bytes")
end)

test("a project with recordings, moved with its folder, plays them", function()
  api.engine_restart({ backend = "null", test_input = { frequency = 440, level = -12, channels = 2 } })
  local ok, err = xpcall(function()
    for _, saved_first in ipairs({ true, false }) do
      fresh()
      local dir = T.scratch .. "/recorded-" .. tostring(saved_first)
      mkdir(dir)
      if saved_first then paw.project.save(dir .. "/song.json") end
      local t = paw.add_track({ name = "Mic" })
      t.input = "1/2"
      t.armed = true
      paw.flush()
      paw.transport.record()
      T.until_beat(paw.transport.position + 1)
      paw.transport.stop()
      paw.flush()
      t.armed = false
      paw.project.save(dir .. "/song.json")
      local file = t:clips()[1].file
      eq(file:sub(1, #dir + 7), dir .. "/media/", "the take is in the project's folder (saved first: " .. tostring(saved_first) .. ")")
      os.rename(dir, dir .. "-moved")
      paw.project.load(dir .. "-moved/song.json")
      local clip = paw.tracks()[1]:clips()[1]
      eq(clip.offline, nil, "the take is found after the move")
      local info = T.render({ start = clip.start, ["end"] = clip.start + clip.length, tail = 0, bits = 16 })
      T.near(info.peak, 10 ^ (-12 / 20), 0.02, "and plays")
    end
  end, debug.traceback)
  api.engine_restart({ backend = "null" })
  if not ok then error(err, 0) end
end)

-- Rendering ----------------------------------------------------------------

--- Adler-32 of a WAV file's samples, and how many bytes they are.
local function checksum(path)
  local d = T.read_file(path)
  local at = d:find("data", 1, true) + 8
  local a, b = 1, 0
  for i = at, #d do a = (a + d:byte(i)) % 65521; b = (b + a) % 65521 end
  return string.format("%d %08x", #d - at + 1, b * 65536 + a)
end

local function u16(s, at) return s:byte(at) + s:byte(at + 1) * 256 end
local function u32(s, at) return u16(s, at) + u16(s, at + 2) * 65536 end

test("a render gives the same samples as the renderer before it moved to a thread", function()
  -- The references were written by the renderer as it was when it ran on
  -- the main thread (commit 330df77), from the demo song: bit for bit.
  dofile("tests/fixtures/render-song.lua")
  local info = paw.render(T.scratch .. "/same32.wav", { bits = 32, tail = 1 })
  eq(info.frames, 870858, "as many frames")
  eq(checksum(info.path), "6966864 29c4bee4", "the same float samples")
  info = paw.render(T.scratch .. "/same24.wav", { bits = 24, tail = 1, normalize = -1, dither = true, start = 4, ["end"] = 12 })
  eq(checksum(info.path), "1522290 feb3b22f", "and the same normalized, dithered 24-bit samples")
end)

test("a render takes a range, a tail, a rate, a channel count and a sample size", function()
  fresh()
  local t = paw.add_track()
  t:add_clip({ file = steady(T.scratch .. "/half.wav", 8, 0.5), start = 0, length = 16 })
  -- At 120 bpm a beat is half a second.
  paw.transport.loop_start, paw.transport.loop_end = 4, 8
  local info = paw.render(T.scratch .. "/loop.wav", { range = "loop", tail = 0 })
  T.near(info.seconds, 2, 1e-3, "the loop is four beats")
  info = paw.render(T.scratch .. "/between.wav", { start = 2, ["end"] = 6, tail = 1.5 })
  T.near(info.seconds, 2 + 1.5, 1e-3, "between two beats, with a tail in seconds")
  T.fails(function() paw.render(T.scratch .. "/sel.wav", { range = "selection" }) end, "selected", "no selection, no range")
  T.fails(function() paw.render(T.scratch .. "/x.wav", { range = "chorus" }) end, "loop", "an unknown range names the known ones")
  paw.render_ranges.chorus = function() return 1, 3 end
  T.near(paw.render(T.scratch .. "/chorus.wav", { range = "chorus", tail = 0 }).seconds, 1, 1e-3, "a range an extension adds")
  paw.render_ranges.chorus = nil

  info = paw.render(T.scratch .. "/mono.wav", { channels = "mono", bits = 16, rate = 44100, ["end"] = 2, tail = 0 })
  local head = T.read_file(info.path)
  eq(u16(head, 23), 1, "one channel")
  eq(u32(head, 25), 44100, "at the rate asked for")
  eq(u16(head, 35), 16, "of 16 bits")
  -- (At 44.1 kHz the file is converted, and its sudden start rings a little.)
  T.near(paw.render(T.scratch .. "/mono48.wav", { channels = 1, ["end"] = 2, tail = 0 }).peak, 0.5, 0.002,
    "both sides mixed at half each")
  T.fails(function() paw.render(T.scratch .. "/x.flac", { bits = 32 }) end, "16, 24", "FLAC has no float samples")
  T.fails(function() paw.render(T.scratch .. "/x.wav", { channels = 6 }) end, "mono", "only mono and stereo")
end)

test("FLAC renders read back as what was rendered", function()
  fresh()
  local t = paw.add_track()
  t:add_clip({ file = steady(T.scratch .. "/flac-src.wav", 3, 0.5), start = 0, length = 4 })
  for _, bits in ipairs({ 16, 24 }) do
    for _, channels in ipairs({ 1, 2 }) do
      local path = string.format("%s/out-%d-%d.flac", T.scratch, bits, channels)
      local info = paw.render(path, { bits = bits, channels = channels, tail = 0 })
      eq(T.read_file(path):sub(1, 4), "fLaC", "a FLAC file")
      local back = paw.add_track()
      local clip = back:add_clip({ file = path, start = 0 })
      T.near(clip.length, 4, 1e-3, string.format("as long as rendered (%d bits, %d channels)", bits, channels))
      eq(info.format, "FLAC", "and says so")
      back:remove()
    end
  end
  local back = paw.add_track()
  back:add_clip({ file = T.scratch .. "/out-24-2.flac", start = 0 })
  t.mute = true
  T.near(T.render({ tail = 0, ["end"] = 3 }).peak, 0.5, 0.0001, "the level comes back")
end)

test("a render can leave out the master, or bring the song to a loudness", function()
  fresh()
  local t = paw.add_track()
  t:add_clip({ file = steady(T.scratch .. "/m.wav", 4, 0.5), start = 0, length = 8 })
  paw.master.volume = -6
  T.near(T.render({ tail = 0 }).peak, 0.25, 0.003, "through the master's fader")
  T.near(T.render({ tail = 0, master = false }).peak, 0.5, 0.001, "and without it")
  paw.master.volume = 0
  local info = T.render({ tail = 0, loudness = -20 })
  T.near(info.loudness, -20, 0.1, "brought to -20 LUFS")
  info = T.render({ tail = 0, loudness = -3, normalize = -6 })
  T.near(info.peak, 10 ^ (-6 / 20), 0.001, "a peak level is a ceiling the loudness gives way to")
end)

--- Wait for the background render to end, gathering its events.
local function finish()
  for _ = 1, 3000 do
    if not paw.render_status() then return end
    paw.wait(10)
  end
  error("the render did not end")
end

test("a render in the background reports progress, can be cancelled, and leaves no partial file", function()
  fresh()
  local t = paw.add_track()
  t:add_clip({ file = steady(T.scratch .. "/bg.wav", 4, 0.5), start = 0, length = 8 })
  local events = {}
  local handles = {}
  for _, name in ipairs({ "render.progress", "render.done", "render.cancelled", "render.failed" }) do
    handles[#handles + 1] = paw.on(name, function(e) events[#events + 1] = { name = name, e = e } end)
  end
  local path = T.scratch .. "/bg-out.wav"
  -- Long, so that there is time to look at it while it runs.
  eq(paw.render(path, { ["end"] = 4000, tail = 0, background = true }), nil, "it returns at once")
  eq(paw.render_status() ~= nil, true, "and is running")
  eq(exists(path), false, "nothing is under the final name while it runs")
  t.volume = -60
  paw.flush()
  T.fails(function() paw.render(T.scratch .. "/other.wav", {}) end, "being rendered", "one render at a time")
  paw.wait(300)
  eq(paw.frontend.state(-1).modal.render ~= nil, true, "the window is told")
  paw.cmd("render.cancel")
  finish()
  eq(exists(path), false, "a cancelled render leaves no file")
  eq(exists(T.scratch .. "/.bg-out.wav.part"), false, "not even a partial one")
  local last = events[#events]
  eq(last and last.name, "render.cancelled", "it says it was cancelled")
  local progress = 0
  for _, ev in ipairs(events) do if ev.name == "render.progress" then progress = math.max(progress, ev.e.fraction) end end
  eq(progress > 0, true, "and reported progress before")

  events = {}
  paw.render(path, { ["end"] = 8, tail = 0, background = true })
  t.volume = 0
  t:clips()[1]:remove()
  paw.flush()
  finish()
  eq(events[#events].name, "render.done", "a render ends with render.done")
  T.near(events[#events].e.peak, 10 ^ (-60 / 20) * 0.5, 0.0005, "of the project as it was when the render started")
  eq(exists(path), true, "under its name")
  for _, h in ipairs(handles) do paw.off(h) end
end)

test("the render command takes its options and completes them", function()
  fresh()
  T.tone("Synth", 2)
  local path = T.scratch .. "/cmd.flac"
  paw.cmd("render", { path, tail = 0, bits = 16, channels = "mono", wait = true })
  eq(T.read_file(path):sub(1, 4), "fLaC", "the command writes FLAC")
  local spec = paw.commands.get("render")
  local words = spec.complete("mix.wav ra")
  local found = false
  for _, w in ipairs(words) do if w == "mix.wav range=" then found = true end end
  eq(found, true, "options complete")
  words = spec.complete("mix.wav range=")
  eq(#words, 3, "and their values: song, loop, selection")
end)

-- Sample rates ----------------------------------------------------------------

--- A file of a tone at `freq` Hz, at `rate`, 16 bits.
local function tone_file(path, rate, freq, seconds, level)
  local s = {}
  for i = 1, math.floor(seconds * rate) do s[i] = level * math.sin(2 * math.pi * freq * (i - 1) / rate) end
  return T.write_wav(path, s, s, rate)
end

test("a file at another rate is converted without aliases, and again when the rate changes", function()
  fresh()
  local t = paw.add_track()
  -- 30 kHz at 96 kHz: above what 48 kHz holds. Linear interpolation folds it
  -- back to 18 kHz at nearly full level; band-limited conversion removes it.
  t:add_clip({ file = tone_file(T.scratch .. "/high96.wav", 96000, 30000, 1, 0.5), start = 0, length = 2 })
  local info = T.render({ tail = 0, bits = 16 })
  local left = T.channel_peaks(info, 0.2, 0.8)
  eq(left < 10 ^ (-70 / 20), true, "nothing above 24 kHz comes through at 48 kHz: peak " .. left)
  info = T.render({ tail = 0, bits = 32, sample_rate = 96000 })
  T.near(info.peak, 0.5, 0.01, "rendered at 96 kHz the tone is all there")
  t:clips()[1]:remove()
  -- 1 kHz at 44.1 kHz plays at its pitch and level.
  t:add_clip({ file = tone_file(T.scratch .. "/a44.wav", 44100, 1000, 1, 0.5), start = 0, length = 2 })
  info = T.render({ tail = 0, bits = 16 })
  T.near(info.peak, 0.5, 0.005, "a tone at 44.1 kHz keeps its level")
  T.near(T.frequency(info, 0.2, 0.8), 1000, 2, "and its pitch")
end)

-- Clip operations on audio -------------------------------------------------------

--- A file rising from 0 to `top` over `seconds`, at 48 kHz.
local function ramp(path, seconds, top)
  local s, n = {}, math.floor(seconds * 48000)
  for i = 1, n do s[i] = top * (i - 1) / n end
  return T.write_wav(path, s)
end

test("an audio clip's edit list: a gain on a part and a pencil fix play through, are saved in the clip's file, and come back without the cache", function()
  fresh()
  T.after(function() api.media_store(0) end)
  -- Every version on the disk: the cache is where it is kept.
  api.media_store(0.0001)
  local _, store = api.media_store()
  local t = paw.add_track({ name = "Take" })
  local src = steady(T.scratch .. "/edit-steady.wav", 2, 0.5)
  local before = T.read_file(src)
  local clip = t:add_clip({ file = src, start = 0, length = 4 })
  paw.flush()
  api.undo_checkpoint()
  paw.cursor.set_track(t)
  paw.cursor.beat = 0
  T.keys(":clip.gain 0.5 1 -120<CR>")
  eq(paw.ui.message.text, clip.name .. ": -120 dB from 0.5 s to 1 s (1 edit in its list)", "said")
  local fix = {}
  for i = 1, 100 do fix[i] = 0.1 end
  paw.media.pencil(clip, 1.5, fix, 0)
  api.undo_checkpoint()
  paw.flush()
  local function heard()
    local s = T.samples(T.render({ tail = 0, bits = 16, ["end"] = 4 }))
    return s
  end
  local s = heard()
  T.near(s[1000], 0.5, 0.01, "the sound before the part")
  T.near(s[36000], 0, 0.001, "the part is silent")
  T.near(s[72010], 0.1, 0.01, "the pencil fix in the left channel")
  T.near(s[60000], 0.5, 0.01, "and the sound after the part")
  eq(T.read_file(src) == before, true, "the file is as it was")
  -- Kept in the bake cache, by what it is made of (bake/store.rs).
  local bakes = assert(os.getenv("XDG_CACHE_HOME"), "a cache of the tests' own") .. "/paw/bakes"
  local found = io.popen("grep -rls '\"op\": \"edit\"' '" .. bakes .. "'"):read("*a")
  eq(found ~= "", true, "the version is in the cache")
  -- Saved: the edit list is in the clip's own file.
  local dir = T.scratch .. "/edits-song"
  paw.project.save(dir)
  local name = clip.name
  local list = api.json_decode(T.read_file(dir .. "/tracks/Take/clips/" .. name .. ".edits.json"))
  eq(#list .. " " .. list[1].kind .. " " .. list[2].kind, "2 gain pencil", "the clip's file holds its edit list")
  -- Without the cache, it is made again.
  os.execute("rm -rf '" .. store .. "' '" .. bakes .. "'")
  paw.project.load(dir)
  paw.flush()
  local again = heard()
  T.near(again[36000], 0, 0.001, "opened again without the cache, the part is silent")
  T.near(again[72010], 0.1, 0.01, "and the fix is there")
  T.keys(":clip.edits.clear<CR>")
  T.near(heard()[36000], 0.5, 0.01, ":clip.edits.clear plays the file again")
end)

test("an audio clip is reversed, normalized and glued without touching its file", function()
  fresh()
  local t = paw.add_track()
  local src = ramp(T.scratch .. "/ramp.wav", 2, 0.5)
  local before = T.read_file(src)
  -- Plays the second half of the file: from 0.25 rising to 0.5.
  local clip = t:add_clip({ file = src, start = 0, length = 2, offset = 1 })
  clip.fade_in = 0.5
  paw.flush()
  api.undo_checkpoint()
  T.keys(":clip.reverse<CR>")
  paw.flush()
  eq(paw.ui.message.text, "reversed " .. clip.name .. " (1 edit in its list; the file stays as it is)", "said")
  eq(clip.file, src, "the clip plays its file")
  eq(paw.media.edits(clip)[1].kind, "reverse", "with a reverse in its edit list")
  eq(clip.offset, 0, "from where the same part is, backwards")
  eq(clip.fade_out, 0.5, "and its fades change ends")
  local s = T.samples(T.render({ tail = 0, bits = 16, ["end"] = 2 }))
  T.near(s[48000 * 0 + 100], 0.5, 0.01, "it starts where it ended")
  T.near(s[30000], 0.5 - 0.25 * 30000 / 48000, 0.01, "and falls towards where it started")
  T.near(s[48000 - 10], 0, 0.01, "fading out at the end, where it faded in before")
  eq(T.read_file(src) == before, true, "the original file is unchanged")
  api.undo_checkpoint()
  paw.undo()
  eq(#paw.media.edits(clip), 0, "one undo step puts it back")
  eq(clip.offset, 1, "offset and all")

  local gain = paw.media.normalize(clip, -6)
  T.near(gain, -6 - 20 * math.log10(0.5), 0.01, "normalizing sets the clip's gain")
  T.near(T.render({ tail = 0, ["end"] = 2 }).peak, 10 ^ (-6 / 20), 0.01, "to bring its peak to the level")
  api.undo_checkpoint()
  paw.undo()

  -- Two clips side by side, and one apart that is left alone.
  local b = t:add_clip({ file = steady(T.scratch .. "/g.wav", 1, 0.25), start = 2, length = 2 })
  local apart = t:add_clip({ file = steady(T.scratch .. "/h.wav", 1, 0.1), start = 8, length = 2 })
  paw.flush()
  local mix = T.render({ tail = 0, bits = 32 })
  api.undo_checkpoint()
  local result = paw.media.glue(clip)
  paw.flush()
  eq(result.glued, 2, "the clip and the one touching it are glued")
  eq(#t:clips(), 2, "into one clip, beside the one apart")
  local glued = paw.clip(result.id)
  eq(glued.start .. "/" .. glued.length, "0/4", "spanning both")
  eq(apart.start, 8, "the clip apart is left alone")
  local after = T.render({ tail = 0, bits = 32 })
  T.near(after.peak, mix.peak, 1e-4, "and it sounds the same")
  api.undo_checkpoint()
  paw.undo()
  eq(#t:clips(), 3, "one undo step brings the clips back")
  T.fails(function() paw.media.glue(apart) end, "nothing to glue", "a clip with nothing beside it")
end)
