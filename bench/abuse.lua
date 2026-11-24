-- Malformed files, missing media, absurd values and limits. Each case runs
-- in its own process (see abuse.sh) so that a crash or a hang is recorded
-- rather than ending the run.
--   paw --clean --no-plugins -l bench/abuse.lua <case>
--   paw --clean --no-plugins -l bench/abuse.lua list
-- A case prints one JSON line: `outcome` is "ok" (it worked and the result is
-- sane), "rejected" (a clean error, with the message) or "BAD" (it went
-- through but left something broken, with what).
local paw = require("paw")
local api = paw.api
local B = dofile(debug.getinfo(1, "S").source:sub(2):match("(.*)/") .. "/lib.lua")

local name = ...
local dir = B.tmp .. "/abuse"
os.execute("mkdir -p '" .. dir .. "'")

local function write(path, text)
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
  return path
end
local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

--- A small valid project file, as text.
local function valid_project()
  local t = api.part_add({ name = "A" })
  api.device_add(t, "synth")
  api.device_add(t, "delay")
  api.clip_add(t, { start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 1 } } })
  api.lane_add(t, { target = "volume", points = { { 0, -6 }, { 4, 0 } } })
  paw.flush()
  local path = api.project_save(dir .. "/valid.json")
  api.project_new()
  paw.flush()
  return read(path)
end

--- Load a project file and check that whatever was loaded can be played,
--- rendered and saved again.
local function load(text)
  local path = write(dir .. "/case.json", text)
  api.project_load(path)
  paw.flush()
  local length = api.project_get().length
  local info = api.render(dir .. "/case.wav", { ["end"] = math.max(1, math.min(length, 8)), tail = 0 })
  if info.nonfinite > 0 then return "BAD", "renders NaN or infinity" end
  api.project_save(dir .. "/again.json")
  local ok, err = pcall(api.project_load, dir .. "/again.json")
  if not ok then return "BAD", "saved a file it cannot load: " .. tostring(err) end
  return "ok", string.format("%d parts, %.1f beats, peak %.3f", #api.part_list(), length, info.peak)
end

local cases = {}
local order = {}
local function case(n, fn)
  cases[n] = fn
  order[#order + 1] = n
end

-- Files ------------------------------------------------------------------------

case("file: empty", function() return load("") end)
case("file: not JSON", function() return load("\0\1\2garbage{{{") end)
case("file: a JSON array", function() return load("[1,2,3]") end)
case("file: truncated in half", function()
  local text = valid_project()
  return load(text:sub(1, math.floor(#text / 2)))
end)
case("file: newer version", function() return load((valid_project():gsub('"version": 1', '"version": 999'))) end)
case("file: tempo 0", function() return load((valid_project():gsub('"tempo": 120.0', '"tempo": 0.0'))) end)
case("file: tempo negative", function() return load((valid_project():gsub('"tempo": 120.0', '"tempo": -5.0'))) end)
case("file: tempo 1e308", function() return load((valid_project():gsub('"tempo": 120.0', '"tempo": 1e308'))) end)
case("file: sig_den 0", function() return load((valid_project():gsub('"sig_den": 4', '"sig_den": 0'))) end)
case("file: clip length -4", function() return load((valid_project():gsub('"length": 4.0', '"length": -4.0', 1))) end)
case(
  "file: clip start 1e300",
  function()
    return load(
      (valid_project():gsub('"start": 0.0,\n        "length": 4.0', '"start": 1e300,\n        "length": 4.0', 1))
    )
  end
)
case("file: note length -1", function() return load((valid_project():gsub('"length": 1.0', '"length": -1.0', 1))) end)
case("file: volume 1e300", function() return load((valid_project():gsub('"volume": 0.0', '"volume": 1e300', 1))) end)
case("file: duplicate part ids", function()
  local text = valid_project()
  local p = text:gsub(
    '"parts": %[',
    '"parts": [ { "id": 1, "name": "dup", "volume": 0.0, "pan": 0.0, "mute": false, "solo": false, "armed": false, "output": null, "sends": [], "devices": [], "clips": [], "color": null },',
    1
  )
  return load(p)
end)
case(
  "file: part routed into itself",
  function() return load((valid_project():gsub('"output": null', '"output": 1', 1))) end
)
case(
  "file: unknown device kind",
  function() return load((valid_project():gsub('"kind": "delay"', '"kind": "no-such-device"', 1))) end
)
case(
  "file: parameter 1e300",
  function() return load((valid_project():gsub('"params": {}', '"params": { "cutoff": 1e300 }', 1))) end
)
case("file: missing audio file", function()
  local t = api.part_add({})
  api.clip_add(t, { start = 0, length = 4, file = B.wav() })
  paw.flush()
  local text = read(api.project_save(dir .. "/audio.json"))
  api.project_new()
  return load((text:gsub("bench%-2s%.wav", "does-not-exist.wav")))
end)
case("file: audio file truncated", function()
  local data = read(B.wav())
  local path = write(dir .. "/truncated.wav", data:sub(1, 5000))
  local t = api.part_add({})
  api.clip_add(t, { start = 0, length = 4, file = path })
  return "ok", "added"
end)
case("file: audio file is text", function()
  local path = write(dir .. "/text.wav", "this is not audio")
  local t = api.part_add({})
  api.clip_add(t, { start = 0, length = 4, file = path })
  return "ok", "added"
end)
case("file: 5000 parts", function()
  local parts = {}
  for i = 1, 5000 do
    parts[i] = string.format(
      '{ "id": %d, "name": "T%d", "volume": 0.0, "pan": 0.0, "mute": false, "solo": false, "armed": false, "output": null, "sends": [], "devices": [{ "id": %d, "kind": "gain", "bypass": false, "params": {} }], "clips": [{ "id": %d, "name": "c", "start": 0.0, "length": 4.0, "muted": false, "content": { "kind": "midi", "notes": [] } }], "color": null }',
      i,
      i,
      100000 + i,
      200000 + i
    )
  end
  local text = '{ "version": 1, "project": { "name": "big", "tempo": 120.0, "sig_num": 4, "sig_den": 4, "master": { "id": 0, "name": "Master", "volume": 0.0, "pan": 0.0, "mute": false, "solo": false, "armed": false, "output": null, "sends": [], "devices": [], "clips": [], "color": null }, "parts": ['
    .. table.concat(parts, ",")
    .. "] } }"
  local outcome, detail = load(text)
  local warnings = api.warnings()
  return outcome, detail .. "; " .. #warnings .. " warnings, first: " .. tostring(warnings[1])
end)

-- Values through the API -------------------------------------------------------------

local function synth_part()
  local t = api.part_add({})
  local d = api.device_add(t, "synth")
  api.clip_add(t, { start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 2 } } })
  paw.flush()
  return t, d
end

--- After an edit that went through, the project must still render cleanly
--- and save to a file that loads.
local function still_sane(what)
  local info = api.render(dir .. "/sane.wav", { ["end"] = 4, tail = 0 })
  if info.nonfinite > 0 then return "BAD", what .. ": the render holds NaN or infinity" end
  api.project_save(dir .. "/sane.json")
  local ok, err = pcall(api.project_load, dir .. "/sane.json")
  if not ok then return "BAD", what .. ": the saved project does not load: " .. tostring(err) end
  return "ok", what .. " went through and nothing broke"
end

case("api: part volume NaN at add", function()
  api.part_add({ volume = 0 / 0 })
  return still_sane("part_add")
end)
case("api: part pan inf at add", function()
  api.part_add({ pan = 1 / 0 })
  return still_sane("part_add")
end)
case("api: parameter NaN", function()
  local _, d = synth_part()
  api.device_set_param(d, "cutoff", 0 / 0)
  return still_sane("device_set_param")
end)
case("api: note start inf", function()
  local t = api.part_add({})
  api.clip_add(t, { start = 0, length = 4, notes = { { pitch = 60, start = 1 / 0, length = 1 } } })
  return still_sane("clip_add")
end)
case("api: note length -1", function()
  local t = synth_part()
  api.clip_add(t, { start = 0, length = 4, notes = { { pitch = 60, start = 0, length = -1 } } })
  -- A note-off before its note-on leaves the note sounding to the end.
  api.render(dir .. "/neg.wav", { start = 0, ["end"] = 16, tail = 0, bits = 16 })
  local tail = api.render(dir .. "/neg2.wav", { start = 12, ["end"] = 16, tail = 0, bits = 16 })
  if tail.peak > 0.001 then
    return "BAD", "a note with a negative length keeps sounding after its clip ends (peak " .. tail.peak .. ")"
  end
  return still_sane("negative note length")
end)
case("api: note pitch 200", function()
  local t = api.part_add({})
  api.clip_add(t, { start = 0, length = 4, notes = { { pitch = 200, start = 0, length = 1 } } })
  return still_sane("pitch 200")
end)
case("api: clip gain NaN", function()
  local t = api.part_add({})
  api.clip_add(t, { start = 0, length = 4, file = B.wav(), gain = 0 / 0 })
  return still_sane("clip gain NaN")
end)
case("api: clip offset -inf", function()
  local t = api.part_add({})
  api.clip_add(t, { start = 0, length = 4, file = B.wav(), offset = -1 / 0 })
  return still_sane("clip offset -inf")
end)
case("api: live note velocity NaN", function()
  local t = synth_part()
  api.device_add(t, "delay")
  api.note_on(t, 60, 0 / 0)
  api.sleep(100)
  local l = api.part_meter(t)
  if l ~= l then return "BAD", "the part's meter reads NaN" end
  return "ok", "meter " .. tostring(l)
end)
case("api: render tail 1e12", function()
  synth_part()
  local t0 = api.real_ms()
  local info = api.render(dir .. "/long.wav", { tail = 1e12 })
  return "BAD", string.format("rendered %s s in %.0f ms", tostring(info.seconds), api.real_ms() - t0)
end)
case("api: render end 1e15", function()
  synth_part()
  local info = api.render(dir .. "/long.wav", { ["end"] = 1e15 })
  return "BAD", "rendered " .. tostring(info.seconds) .. " s"
end)
case("api: render sample rate 0", function()
  synth_part()
  local info = api.render(dir .. "/sr0.wav", { sample_rate = 0 })
  return "BAD", "rendered at 0 Hz: " .. tostring(info.frames) .. " frames"
end)
case("api: render sample rate 4e9", function()
  local _ = synth_part()
  api.device_add(api.part_list()[1], "delay")
  api.render(dir .. "/sr4e9.wav", { sample_rate = 4000000000, ["end"] = 0.001, tail = 0 })
  return "BAD", "rendered at 4 GHz"
end)
case("api: engine sample rate 0", function()
  api.engine_restart({ backend = "null", sample_rate = 0 })
  synth_part()
  api.transport_play()
  api.sleep(200)
  return "BAD", "the engine runs at 0 Hz: " .. paw.inspect(api.engine_get().sample_rate)
end)
case("api: engine buffer 0", function()
  api.engine_restart({ backend = "null", buffer_size = 0 })
  synth_part()
  api.transport_play()
  api.sleep(200)
  return "ok", "buffer " .. tostring(api.engine_get().buffer_size)
end)
case("api: engine buffer 1e9", function()
  api.engine_restart({ backend = "null", buffer_size = 1000000000 })
  synth_part()
  api.transport_play()
  api.sleep(200)
  return "BAD", "the engine took a buffer of 1e9 frames"
end)
case("api: tiny loop under load", function()
  for _ = 1, 50 do
    synth_part()
  end
  paw.transport.loop_start, paw.transport.loop_end = 0, 0.0001
  paw.transport.loop_enabled = true
  api.engine_reset_stats()
  api.transport_play()
  api.sleep(1000)
  local b = api.engine_get().blocks
  local load = b.max / b.budget
  if load > 1 then return "BAD", string.format("a 0.0001-beat loop takes %.1f times the time a block has", load) end
  return "ok", string.format("worst block %.2f of its budget", load)
end)
case("api: seek to 1e300 and play", function()
  synth_part()
  api.transport_seek(1e300)
  api.transport_play()
  api.sleep(100)
  return "ok", "position " .. tostring(api.transport_get().position)
end)
case("api: 2000 parts", function()
  for i = 1, 2000 do
    api.part_add({})
  end
  paw.flush()
  local warnings = api.warnings()
  -- Remove the first 1000: the rest should now all get an engine slot.
  local list = api.part_list()
  for i = 1, 1000 do
    api.part_remove(list[i])
  end
  paw.flush()
  local t = list[2000]
  api.device_add(t, "synth")
  api.clip_add(t, { start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 2 } } })
  paw.flush()
  api.note_on(t, 60, 100)
  api.sleep(150)
  local l = api.part_meter(t)
  if l == 0 then return "BAD", #warnings .. " warnings; part 2000 stays silent after 1000 parts were removed" end
  return "ok", #warnings .. " warnings, part 2000 sounds once there is room"
end)
case("api: 10000 devices", function()
  local t = api.part_add({})
  local ok, err
  for i = 1, 10000 do
    ok, err = pcall(api.device_add, t, "gain")
    if not ok then break end
  end
  return ok and "BAD" or "rejected", tostring(err)
end)
case("api: 1e6 notes in one clip", function()
  local t = api.part_add({})
  api.device_add(t, "synth")
  local notes = {}
  for i = 1, 1000000 do
    notes[i] = { pitch = 36 + i % 48, start = i * 0.001, length = 0.01 }
  end
  local t0 = api.real_ms()
  api.clip_add(t, { start = 0, length = 1001, notes = notes })
  paw.flush()
  local add = api.real_ms() - t0
  t0 = api.real_ms()
  api.render(dir .. "/many.wav", { ["end"] = 64, tail = 0 })
  return "ok", string.format("added in %.0f ms, rendered 64 beats in %.0f ms", add, api.real_ms() - t0)
end)

if name == "list" then
  for _, n in ipairs(order) do
    print(n)
  end
  api.quit(0)
  return
end
local fn = cases[name]
if not fn then error("no case " .. tostring(name)) end
local t0 = api.real_ms()
local ok, outcome, detail = pcall(fn)
local record = { workload = "abuse", case = name, ms = api.real_ms() - t0 }
if ok then
  record.outcome, record.detail = outcome, detail
else
  local msg = tostring(outcome):gsub("\nstack traceback:.*", "")
  record.outcome = "rejected"
  record.detail = msg
  for _, bad in ipairs({ "panicked", "attempt to", "unwrap" }) do
    if msg:find(bad, 1, true) then record.outcome = "BAD" end
  end
end
B.emit(record)
os.execute("rm -rf '" .. dir .. "'")
api.quit(0)
