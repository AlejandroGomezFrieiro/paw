-- Tests of not losing work: saving, opening a damaged project, recording
-- takes that end badly, devices that fail, the engine's counters.
local T = ...
local test, eq, fresh, render = T.test, T.eq, T.fresh, T.render
local paw = require("paw")
local api = paw.api

test("a project saved before the safety work still opens", function()
  fresh()
  paw.project.load("tests/fixtures/demo-song.json")
  local names = {}
  for _, t in ipairs(paw.tracks()) do
    names[#names + 1] = t.name
  end
  eq(table.concat(names, ","), "Drums,Bass,Keys,Lead,Reverb", "its tracks")
  eq(paw.project.tempo, 112, "its tempo")
  eq(#paw.tracks()[1]:clips(), 8, "its clips")
  eq(paw.project.modified, false, "and nothing is changed by opening it")
end)

test("saving keeps the previous file as .bak and leaves no temporary file", function()
  fresh()
  local path = T.scratch .. "/bak-song.json"
  paw.add_track({ name = "First" })
  paw.project.save(path)
  eq(io.open(path .. ".bak"), nil, "a first save has nothing to keep")
  paw.add_track({ name = "Second" })
  paw.project.save(path)
  local bak = T.read_file(path .. ".bak")
  eq(
    bak:find('"First"', 1, true) ~= nil and bak:find('"Second"', 1, true) == nil,
    true,
    "the .bak is the file as it was"
  )
  eq(T.read_file(path):find('"Second"', 1, true) ~= nil, true, "the file is the project as it is")
  eq(io.open(path .. ".tmp"), nil, "no temporary file is left")
end)

test("a project that will not parse offers its .bak and its newest safety copy", function()
  fresh()
  local autosave = paw.autosave
  local dir = T.scratch .. "/recovery-damaged"
  local old_dir = autosave.dir
  autosave.dir = dir
  local path = T.scratch .. "/damaged.json"
  paw.add_track({ name = "Saved once" })
  paw.project.save(path)
  paw.add_track({ name = "Saved twice" })
  paw.project.save(path)
  -- A safety copy of later work, from a session that ended badly.
  paw.add_track({ name = "Never saved" })
  api.project_backup(dir .. "/damaged-copy.json", { path = path, name = "damaged", time = os.time(), pid = 999999999 })
  -- The file is cut short, as a full disk or a bad copy would leave it.
  local text = T.read_file(path)
  T.write_file(path, text:sub(1, math.floor(#text / 2)))

  paw.project.new()
  local ok, err = pcall(paw.project.load, path)
  eq(ok, false, "the damaged file does not open")
  eq(
    tostring(err):find(":recover", 1, true) ~= nil,
    true,
    "the error says what can be opened instead: " .. tostring(err)
  )
  local choices = autosave.choices()
  eq(#choices >= 2, true, "two stand-ins are offered")
  eq(
    choices[1].name .. "|" .. choices[2].name,
    "safety copy|backup (before the last save)",
    "the safety copy first, then the backup"
  )

  paw.commands.exec("recover 2")
  local names = {}
  for _, t in ipairs(paw.tracks()) do
    names[#names + 1] = t.name
  end
  eq(table.concat(names, ","), "Saved once", "the backup is the file before the last save")
  eq(paw.project.path, path, "and opens as the damaged project's file")
  eq(paw.project.modified, true, "unsaved until saved over it")

  pcall(paw.project.load, path)
  paw.commands.exec("recover! 1")
  eq(#paw.tracks(), 3, "the safety copy has the later work")
  paw.project.save()
  eq(pcall(paw.project.load, path), true, "and once saved, the project opens again")
  autosave.dir = old_dir
end)

test(
  "a project folder keeps its project.toml as .bak, and :recover opens it with the folder when project.toml is damaged",
  function()
    fresh()
    local autosave = paw.autosave
    local old_dir = autosave.dir
    autosave.dir = T.scratch .. "/recovery-damaged-folder"
    T.after(function() autosave.dir = old_dir end)
    local dir = T.scratch .. "/damaged-folder"
    local first = paw.add_track({ name = "First" })
    first:add_clip({ start = 0, length = 4, notes = { { start = 0, length = 1, pitch = 60 } } })
    paw.project.save(dir)
    eq(io.open(dir .. "/project.toml.bak"), nil, "a first save has nothing to keep")
    paw.add_track({ name = "Second" })
    api.undo_checkpoint()
    T.keys(":w<CR>")
    local bak = T.read_file(dir .. "/project.toml.bak")
    eq(
      bak:find('"First"', 1, true) ~= nil and bak:find('"Second"', 1, true) == nil,
      true,
      "the .bak is project.toml as it was"
    )
    -- project.toml is cut short.
    local text = T.read_file(dir .. "/project.toml")
    T.write_file(dir .. "/project.toml", text:sub(1, 12))
    T.keys(":e! " .. dir .. "<CR>")
    local said = {}
    for i = math.max(1, #paw.ui.messages - 4), #paw.ui.messages do
      said[#said + 1] = paw.ui.messages[i].text
    end
    said = table.concat(said, "\n")
    eq(
      said:find("damaged-folder will not open; `:recover` opens its backup instead", 1, true) ~= nil,
      true,
      "says what opens instead: " .. said
    )
    eq(paw.autosave.choices()[1].name, "backup (before the last save)", ":recover lists project.toml.bak first")
    T.keys(":recover 1<CR>")
    local names = {}
    for _, t in ipairs(paw.tracks()) do
      names[#names + 1] = t.name
    end
    eq(table.concat(names, ","), "First", "the tracks of the project file before the last save")
    eq(#paw.tracks()[1]:clips()[1]:notes(), 1, "with the clip read from its file")
    eq(paw.project.path, dir .. "/project.toml", "it opens as the damaged project")
    eq(paw.project.modified, true, "unsaved until saved over it")
    T.keys(":w<CR>")
    eq(pcall(paw.project.load, dir), true, "and once saved, the project opens again")
    eq(#paw.tracks(), 1, "as it was recovered")
  end
)

-- Recording ------------------------------------------------------------------

local function with_input(fn)
  api.engine_restart({ backend = "null", test_input = { frequency = 440, level = -12, channels = 2 } })
  local ok, err = xpcall(fn, debug.traceback)
  api.engine_restart({ backend = "null" })
  if not ok then error(err, 0) end
end

--- The data size a WAV file's header gives, and the file's length.
local function wav_sizes(path)
  local data = T.read_file(path)
  local b1, b2, b3, b4 = data:byte(41, 44)
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216, #data
end

test("a take's file is a valid WAV while it is recorded, and is in the safety copy from the start", function()
  with_input(function()
    fresh()
    local dir = T.scratch .. "/take-progress"
    os.execute("mkdir -p '" .. dir .. "'")
    paw.project.save(dir .. "/song.json")
    local mic = paw.add_track({ name = "mic" })
    mic.input, mic.armed = "1", true
    api.undo_checkpoint()
    local files
    local handle = paw.on("transport.record", function(e) files = e.files end)
    paw.transport.record()
    paw.flush()
    paw.off(handle)
    eq(files and #files, 1, "the take's file is named when it begins")
    -- A safety copy made now has the take in it.
    local copy = T.scratch .. "/take-copy.json"
    api.project_backup(copy, { path = dir .. "/song.json", time = os.time(), pid = 999999999 })
    paw.wait(2600)
    local size, length = wav_sizes(files[1])
    eq(size > 48000 * 4, true, "the header counts what was written a moment ago: " .. size)
    eq(size <= length - 44, true, "and no more than is in the file")
    paw.transport.stop()
    eq(#mic:clips(), 1, "stopping makes the clip")
    paw.project.new()
    api.project_recover(copy)
    local back = paw.tracks()[1]:clips()
    eq(#back, 1, "recovering the copy puts the take back as a clip")
    eq(back[1].file, files[1], "from its file")
    eq(back[1].length > 4, true, "with what the file holds: " .. back[1].length .. " beats")
  end)
end)

test("starting to record with little room on the disk says how many minutes are left", function()
  with_input(function()
    fresh()
    os.execute("mkdir -p '" .. T.scratch .. "/take-disk'")
    paw.project.save(T.scratch .. "/take-disk/song.json")
    local mic = paw.add_track({ name = "mic" })
    mic.input, mic.armed = "1/2", true
    paw.opt.record_warn_minutes = 1e12
    paw.transport.record()
    paw.flush()
    paw.opt.record_warn_minutes = nil
    paw.transport.stop()
    local found
    for _, m in ipairs(paw.ui.messages) do
      if m.text:find("minutes? of recording") then found = m.text end
    end
    eq(found ~= nil, true, "a warning names the minutes left")
  end)
end)

test("takes in media/ that no clip refers to are offered on open", function()
  fresh()
  local dir = T.scratch .. "/take-orphans"
  paw.add_track({ name = "Guitar" })
  os.execute("mkdir -p '" .. dir .. "/media'")
  -- A take recorded and then undone before the last save is not offered.
  T.write_file(dir .. "/media/Guitar-take1.wav", T.read_file("tests/fixtures/shape.wav"))
  os.execute("touch -d '1 hour ago' '" .. dir .. "/media/Guitar-take1.wav'")
  paw.project.save(dir .. "/song.json")
  os.execute("touch -d '1 minute ago' '" .. dir .. "/song.json'")
  -- One written after it, by a session that never saved again, is.
  T.write_file(dir .. "/media/Guitar-take3.wav", T.read_file("tests/fixtures/shape.wav"))
  T.write_file(dir .. "/media/drums.wav", T.read_file("tests/fixtures/shape.wav"))
  paw.project.new()
  paw.project.load(dir .. "/song.json")
  paw.flush()
  local found
  for _, m in ipairs(paw.ui.messages) do
    if m.text:find("1 recorded take in media/", 1, true) then found = true end
  end
  eq(found, true, "opening the project says a take is not in it")
  local takes = paw.autosave.orphan_takes()
  eq(#takes .. takes[1].name, "1Guitar-take3.wav", "only the take, not other media")
  local choices = paw.autosave.choices()
  local n
  for i, c in ipairs(choices) do
    if c.take then n = i end
  end
  paw.commands.exec("recover " .. n)
  eq(#paw.tracks(), 1, "it is brought in on the track it was recorded for")
  eq(#paw.tracks()[1]:clips(), 1, "as a clip")
  eq(#paw.autosave.orphan_takes(), 0, "and is no longer offered")
end)

-- Devices that fail ---------------------------------------------------------

--- Largest difference between two lists of samples, from frame `from` on.
local function largest_difference(a, b, from)
  local worst = 0
  for i = from or 1, math.min(#a, #b) do
    worst = math.max(worst, math.abs(a[i] - b[i]))
  end
  return worst
end

test("a device that panics is bypassed and reported, and the rest plays on", function()
  fresh()
  api.test_devices()
  T.tone("steady", 8)
  local other = T.tone("other", 8, "E4")
  local bad = other:add_device("test.panic")
  local before = render({ ["end"] = 2, tail = 0 })
  bad:set("fail", 1)
  local after = render({ ["end"] = 2, tail = 0 })
  eq(after.nonfinite or 0, 0, "the render is finite")
  -- The block it panicked in is silent on its track; after that it is passed over.
  local a, b = T.samples(before), T.samples(after)
  eq(#a, #b, "the same length")
  eq(largest_difference(a, b, 4097) < 1e-3, true, "everything else is as it was: " .. largest_difference(a, b, 4097))

  -- Playing: the device is reported as stopped, and the other track sounds.
  local stopped
  local handle = paw.on("device.stopped", function(e) stopped = e end)
  paw.transport.play()
  paw.wait(400)
  paw.off(handle)
  eq(stopped and stopped.device, bad.id, "device.stopped names it")
  eq(
    stopped and stopped.reason:find("crashed", 1, true) ~= nil,
    true,
    "and says why: " .. tostring(stopped and stopped.reason)
  )
  eq(api.device_get(bad.id).stopped ~= nil, true, "the device shows it has stopped")
  eq(select(1, paw.tracks()[1]:meter()) > 0.01, true, "the other track still sounds")
  local left, right = paw.master:meter()
  eq(left == left and right == right and left < 10, true, "the master is finite")
  eq(select(1, other:meter()) > 0.01, true, "and its own track plays on, through it")
  paw.transport.stop()
  bad:set("fail", 0)
  bad:restart()
  eq(api.device_get(bad.id).stopped, nil, "restarted, it works again")
end)

test("a device that puts out NaN is silenced at its output and reported once", function()
  fresh()
  api.test_devices()
  T.tone("steady", 8)
  local alone = render({ ["end"] = 2, tail = 0 })
  local other = T.tone("other", 8, "E4")
  other:add_device("test.nan", { fail = 1 })
  local info = render({ ["end"] = 2, tail = 0 })
  eq(info.nonfinite or 0, 0, "nothing invalid reaches the master")
  eq(largest_difference(T.samples(alone), T.samples(info)) < 1e-3, true, "and the mix is the other track alone")

  local said = 0
  local handle = paw.on("device.invalid", function() said = said + 1 end)
  paw.transport.play()
  paw.wait(500)
  paw.transport.stop()
  paw.off(handle)
  eq(said, 1, "said once, not every block")
  local left = paw.master:meter()
  eq(left == left, true, "the master meter is a number")
  local l2 = other:meter()
  eq(l2, 0, "the track's meter reads silence")
end)

test(
  "a plugin that hangs in processing is ended and reported, the rest plays on, and a render does not wait for it",
  function()
    local kind
    for _, info in ipairs(paw.device_types()) do
      if info.format == "clap" and info.name:find("Limiter Stereo$") then kind = info.kind end
    end
    if not kind then return "skipped: test plugins not found" end
    fresh()
    local steady = T.tone("steady", 16)
    local other = T.tone("other", 16, "E4")
    local fx = other:add_device(kind)
    if not pcall(api.device_call, fx.id, "sandbox.pid") then return "skipped: plugins are hosted in-process here" end
    -- One that is not told to hang, to tell the helpers made later to answer again.
    local helper = T.tone("helper", 1):add_device(kind)
    local stopped
    local handler = paw.on("device.stopped", function(e)
      if e.device == fx.id then stopped = e end
    end)
    api.device_call(fx.id, "sandbox.hang")
    local ok, err = xpcall(function()
      paw.transport.play()
      local began = api.now()
      while not stopped and api.now() - began < 8000 do
        paw.wait(100)
      end
      local waited = api.now() - began
      eq(stopped and stopped.device, fx.id, "the plugin is reported")
      eq(waited < 4500, true, "within a few seconds: " .. waited .. " ms")
      eq(stopped.reason:find("stopped answering", 1, true) ~= nil, true, "as not answering: " .. stopped.reason)
      eq(paw.transport.playing and paw.transport.position > 1, true, "the transport kept running")
      eq(select(1, steady:meter()) > 0.01, true, "the other track sounds")
      eq(select(1, other:meter()) > 0.01, true, "its own track plays on, the effect passed through")
      paw.transport.stop()

      -- A render makes instances of its own, which hang too: it goes on without them.
      began = api.now()
      local info = render({ ["end"] = 8, tail = 0 })
      local took = api.now() - began
      eq(took < 5000, true, "the render waits for it once, briefly: " .. took .. " ms")
      eq(info.peak > 0.05, true, "and has the rest of the song")
      paw.flush()
      -- By time, not by count: the list holds 500 messages at most.
      local said = false
      for _, m in ipairs(paw.ui.messages) do
        if m.time >= began and m.text:find("stopped during the render", 1, true) then said = true end
      end
      eq(said, true, "the render says what it left out")
    end, debug.traceback)
    paw.off(handler)
    paw.transport.stop()
    pcall(api.device_call, helper.id, "sandbox.hang", "0")
    if not ok then error(err, 0) end
    fx:restart()
    eq(api.device_get(fx.id).stopped, nil, "restarted, it works again")
    paw.transport.play()
    paw.wait(600)
    paw.transport.stop()
    eq(api.device_get(fx.id).stopped, nil, "and keeps answering")
  end
)

-- Long sessions and counters -------------------------------------------------

test("decoded audio no clip or undo step refers to is let go", function()
  fresh()
  local file = T.write_wav(T.scratch .. "/keep-me.wav", { 0.1, 0.2, 0.3, 0.4 })
  local t = paw.add_track()
  t:add_clip({ file = file, start = 0 })
  api.undo_checkpoint()
  eq(api.engine_get().audio_files, 1, "a file in use is held")
  paw.project.new()
  eq(api.engine_get().audio_files, 0, "a new project lets it go")
  t = paw.add_track()
  local clip = t:add_clip({ file = file, start = 0 })
  api.undo_checkpoint()
  clip:remove()
  api.undo_checkpoint()
  paw.project.load("tests/fixtures/demo-song.json")
  eq(api.engine_get().audio_files, 0, "opening a project lets go of what the last one used")
end)

test("the engine's counters of what went wrong are read in one call and shown by :engine.status", function()
  fresh()
  local e = api.engine_get()
  for _, key in ipairs({ "xruns", "late_blocks", "midi_dropped", "record_dropped", "devices_stopped" }) do
    eq(type(e[key]), "number", key .. " is a number")
  end
  local s = paw.frontend.state(-1)
  eq(type(s.xruns) .. type(s.late_blocks) .. type(s.midi_dropped), "numbernumbernumber", "and in the frontend's state")
  paw.commands.exec("engine.status")
  eq(
    paw.ui.messages[#paw.ui.messages].text:find("late plugin blocks", 1, true) ~= nil,
    true,
    ":engine.status prints them"
  )
end)

-- Relative media paths ------------------------------------------------------

test("a .bak names its media relative to the project and opens with them", function()
  fresh()
  local dir = T.scratch .. "/bak-relative"
  os.execute("mkdir -p '" .. dir .. "/media'")
  local file = T.write_wav(dir .. "/media/riff.wav", { 0.1, 0.2, 0.3, 0.4 })
  paw.add_track({ name = "Gtr" }):add_clip({ file = file, start = 0 })
  local path = dir .. "/song.json"
  paw.project.save(path)
  paw.tracks()[1].volume = -3
  paw.project.save(path)
  eq(T.read_file(path .. ".bak"):find('"media/riff.wav"', 1, true) ~= nil, true, "the .bak holds the relative path")
  T.write_file(path, "{ broken")
  paw.project.new()
  pcall(paw.project.load, path)
  local n
  for i, c in ipairs(paw.autosave.choices()) do
    if c.as_path then n = i end
  end
  paw.commands.exec("recover " .. n)
  local clip = paw.tracks()[1]:clips()[1]
  eq(clip.file, file, "its clip is the file beside the project")
  eq(#api.media_missing(), 0, "and nothing is missing")
end)

test("takes of a project whose folder moved are not offered when the project uses them", function()
  with_input(function()
    fresh()
    local dir = T.scratch .. "/take-moved"
    os.execute("mkdir -p '" .. dir .. "'")
    paw.project.save(dir .. "/song.json")
    local mic = paw.add_track({ name = "mic" })
    mic.input, mic.armed = "1", true
    paw.transport.record()
    paw.wait(600)
    paw.transport.stop()
    paw.project.save()
    paw.project.new()
    os.execute("mv '" .. dir .. "' '" .. dir .. "-moved'")
    paw.project.load(dir .. "-moved/song.json")
    paw.flush()
    eq(#paw.autosave.orphan_takes(), 0, "the take the project uses is not offered")
    local clip = paw.tracks()[1]:clips()[1]
    eq(clip.file:find(dir .. "-moved/media/", 1, true) == 1, true, "and plays from the moved folder: " .. clip.file)
  end)
end)
