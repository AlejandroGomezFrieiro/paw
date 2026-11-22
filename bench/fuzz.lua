-- Drive random sequences of API calls with a fixed seed and check invariants
-- as it goes:
--   * no crash and no panic (the run must reach its end and exit 0)
--   * every error is a clean rejection: a message from the API, never a Lua
--     runtime error or a Rust panic message
--   * undo then redo returns to the same project
--   * saving changes nothing; a project folder saved, loaded and saved
--     again gives the same files, and loads as the same project (the first
--     load puts notes on the tick grid of a clip file)
--   * rendering the same project twice gives the same bytes, with devices
--     at rest asleep and without; and renders never contain NaN or infinity
--   * every id a view lists can be looked up
--
--   XDG_DATA_HOME=<scratch> paw --clean --no-plugins -l bench/fuzz.lua <seed> <steps> [verbose]
--
-- Prints one JSON line with what it did, and exits 1 on the first broken
-- invariant, naming the seed and step to reproduce it.
local paw = require("paw")
local api = paw.api
local B = dofile(debug.getinfo(1, "S").source:sub(2):match("(.*)/") .. "/lib.lua")

local seed, steps, verbose = ...
seed, steps = tonumber(seed) or 1, tonumber(steps) or 1000
local dir = B.tmp .. "/fuzz-" .. seed
os.execute("rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "'")

-- A generator of our own, so that runs repeat whatever math.random is.
local state = seed * 2654435761 % 4294967296 + 1
local function rand()
  state = (state * 1103515245 + 12345) % 2147483648
  return state / 2147483648
end
local function int(a, b) return a + math.floor(rand() * (b - a + 1)) end
local function pick(list) return list[int(1, #list)] end
local function chance(p) return rand() < p end

local NAN, INF = 0 / 0, 1 / 0
local function weird_number() return pick({ NAN, INF, -INF, 1e300, -1e300, -1, 0, 1e-320, 2 ^ 53, -(2 ^ 31), 1e9 }) end
local function number(a, b)
  if chance(0.05) then return weird_number() end
  return a + rand() * (b - a)
end

local wav = B.wav()
local stats = { ops = 0, rejected = 0, checks = { undo = 0, save = 0, render = 0, views = 0 }, errors = {} }

local function fail(step, what, detail)
  -- Keep the project that broke, to look at.
  local kept = pcall(api.project_save, B.tmp .. "/fuzz-failed-" .. seed)
  B.emit({
    workload = "fuzz",
    seed = seed,
    step = step,
    failed = what,
    detail = detail,
    project = kept and (B.tmp .. "/fuzz-failed-" .. seed) or nil,
  })
  io.stdout:flush()
  api.quit(1)
  error("stop", 0)
end

-- Error messages that are not a clean rejection of bad input.
local BAD = { "panicked", "attempt to", "stack overflow", "unwrap", "RefCell", "already borrowed", "index out of" }

local function tracks() return api.track_list() end
local function any_track()
  local list = tracks()
  if #list == 0 or chance(0.05) then return chance(0.5) and 0 or int(-5, 100000) end
  return pick(list)
end
local function all(kind)
  local out = {}
  for _, t in ipairs(tracks()) do
    local view = api.track_get(t)
    for _, id in ipairs(view[kind]) do
      out[#out + 1] = id
    end
  end
  for _, id in ipairs(api.track_get(0)[kind]) do
    out[#out + 1] = id
  end
  return out
end
local function any_of(kind)
  local list = all(kind)
  if #list == 0 or chance(0.05) then return int(1, 100000) end
  return pick(list)
end
local function any_lane()
  local out = {}
  for _, t in ipairs(tracks()) do
    for _, l in ipairs(api.lane_list(t)) do
      out[#out + 1] = l.id
    end
  end
  if #out == 0 or chance(0.05) then return int(1, 100000) end
  return pick(out)
end

local function notes(n)
  local list = {}
  for i = 1, n do
    list[i] = {
      pitch = chance(0.03) and pick({ 128, 255, -1, 1000 }) or int(0, 127),
      start = chance(0.03) and weird_number() or rand() * 8,
      length = chance(0.03) and weird_number() or rand() * 2,
      velocity = chance(0.03) and pick({ 0, 127, 128, 255, 1000 }) or int(1, 127),
    }
  end
  return list
end

local ops = {
  {
    8,
    "track_add",
    function()
      local opts = { name = chance(0.02) and string.rep("x", 10000) or "T" }
      if chance(0.2) then opts.volume = number(-60, 12) end
      if chance(0.2) then opts.pan = number(-1, 1) end
      if chance(0.1) then opts.index = int(-3, 30) end
      if chance(0.1) then opts.output = any_track() end
      if chance(0.02) then opts.bogus = 1 end
      -- Keep projects small, except now and then.
      if #tracks() > 12 and not chance(0.02) then return end
      api.track_add(opts)
    end,
  },
  { 2, "track_remove", function() api.track_remove(any_track()) end },
  { 2, "track_move", function() api.track_move(any_track(), int(0, 20)) end },
  {
    10,
    "track_set",
    function()
      local key = pick({
        "volume",
        "pan",
        "mute",
        "solo",
        "armed",
        "monitor",
        "output",
        "sends",
        "input",
        "name",
        "color",
        "nope",
      })
      local value
      if key == "volume" or key == "pan" then
        value = number(-100, 30)
      elseif key == "mute" or key == "solo" or key == "armed" or key == "monitor" then
        value = chance(0.5)
      elseif key == "output" then
        value = chance(0.3) and nil or any_track()
      elseif key == "sends" then
        value = chance(0.3) and {} or { { target = any_track(), level = number(-60, 6) } }
      elseif key == "input" then
        value = pick({ "1", "1/2", "2/3", "3", "0", "1/3", "", nil, 7, "x" })
      else
        value = chance(0.8) and "name" or 42
      end
      api.track_set(any_track(), key, value)
    end,
  },
  {
    6,
    "device_add",
    function()
      local kind = chance(0.05) and "nonexistent" or pick({ "synth", "drums", "gain", "delay" })
      local opts = nil
      if chance(0.3) then opts = { params = { gain = number(-60, 12), cutoff = number(20, 20000) } } end
      if chance(0.1) then opts = { index = int(-2, 10) } end
      if chance(0.3) and kind ~= "nonexistent" then opts = nil end
      api.device_add(any_track(), kind, opts)
    end,
  },
  { 2, "device_remove", function() api.device_remove(any_of("devices")) end },
  { 2, "device_move", function() api.device_move(any_of("devices"), any_track(), int(0, 5)) end },
  {
    8,
    "device_set_param",
    function()
      local name = pick({
        "gain",
        "cutoff",
        "resonance",
        "wave",
        "attack",
        "release",
        "time",
        "feedback",
        "mix",
        "decay",
        "kick_tune",
        "nope",
      })
      api.device_set_param(any_of("devices"), name, number(-100, 20000))
    end,
  },
  {
    2,
    "device_set",
    function() api.device_set(any_of("devices"), pick({ "bypass", "meta", "nope" }), chance(0.5)) end,
  },
  {
    8,
    "clip_add",
    function()
      local opts = { start = number(0, 16), length = chance(0.8) and number(0.25, 8) or nil }
      if chance(0.25) then
        opts.file = chance(0.9) and wav or (dir .. "/missing.wav")
        if chance(0.3) then opts.offset = number(-1, 3) end
        if chance(0.3) then opts.gain = number(-30, 6) end
      else
        opts.notes = notes(int(0, chance(0.05) and 3000 or 20))
      end
      if chance(0.02) then opts.kind = "video" end
      api.clip_add(any_track(), opts)
    end,
  },
  { 3, "clip_remove", function() api.clip_remove(any_of("clips")) end },
  {
    8,
    "clip_set",
    function()
      local key = pick({ "start", "length", "muted", "track", "gain", "offset", "name", "nope" })
      local value
      if key == "muted" then
        value = chance(0.5)
      elseif key == "track" then
        value = any_track()
      elseif key == "name" then
        value = "c"
      else
        value = number(-4, 16)
      end
      api.clip_set(any_of("clips"), key, value)
    end,
  },
  {
    5,
    "clip_notes",
    function()
      if chance(0.5) then
        api.clip_set_notes(any_of("clips"), notes(int(0, 30)))
      else
        api.clip_add_notes(any_of("clips"), notes(int(1, 10)))
      end
    end,
  },
  {
    4,
    "lane_add",
    function()
      local track = any_track()
      local opts = { target = pick({ "volume", "pan", "param", "tempo" }), points = {} }
      for i = 1, int(0, 6) do
        opts.points[i] = { number(0, 16), number(-60, 6) }
      end
      if opts.target == "param" then
        opts.device = any_of("devices")
        opts.param = pick({ "cutoff", "gain", "mix", "nope" })
      end
      api.lane_add(track, opts)
    end,
  },
  {
    4,
    "lane_points",
    function()
      local lane = any_lane()
      if chance(0.5) then
        api.lane_add_point(lane, number(0, 16), number(-60, 6))
      else
        local points = {}
        for i = 1, int(0, 8) do
          points[i] = { number(0, 16), number(-60, 6) }
        end
        api.lane_set_points(lane, points)
      end
    end,
  },
  {
    2,
    "lane_misc",
    function()
      if chance(0.5) then
        api.lane_remove(any_lane())
      else
        api.lane_set(any_lane(), "enabled", chance(0.5))
      end
    end,
  },
  {
    3,
    "project_set",
    function()
      local key = pick({ "tempo", "sig_num", "sig_den", "name", "nope" })
      local value = key == "name" and "p" or number(-10, 400)
      if key == "sig_num" or key == "sig_den" then value = int(-2, 70) end
      api.project_set(key, value)
    end,
  },
  { 10, "undo", function() api.undo() end },
  { 6, "redo", function() api.redo() end },
  {
    6,
    "transport",
    function()
      local what = int(1, 6)
      if what == 1 then
        api.transport_play()
      elseif what == 2 then
        api.transport_stop()
      elseif what == 3 then
        api.transport_seek(number(0, 32))
      elseif what == 4 then
        api.transport_set(pick({ "loop_enabled", "metronome" }), chance(0.5))
      elseif what == 5 then
        api.transport_set(pick({ "loop_start", "loop_end" }), number(0, 32))
      else
        api.transport_set("recording", chance(0.5))
      end
    end,
  },
  {
    3,
    "notes_live",
    function()
      if chance(0.5) then
        api.note_on(any_track(), int(0, 127), chance(0.1) and weird_number() or int(0, 127))
      else
        api.midi_inject({ type = pick({ "note_on", "note_off", "cc" }), pitch = int(0, 140), velocity = int(0, 127) })
      end
    end,
  },
  {
    1,
    "engine_restart",
    function()
      local opts = {
        backend = "null",
        buffer_size = pick({ 16, 64, 128, 512, 1024, 4096 }),
        sample_rate = pick({ 22050, 44100, 48000, 96000 }),
      }
      if chance(0.3) then opts.test_input = { frequency = 440, level = -12, channels = int(1, 4) } end
      api.engine_restart(opts)
    end,
  },
  {
    1,
    "record",
    function()
      api.transport_set("recording", true)
      api.transport_play()
      api.sleep(int(5, 40))
      api.transport_stop()
    end,
  },
}

local total = 0
for _, op in ipairs(ops) do
  total = total + op[1]
end
local function choose()
  local r = rand() * total
  for _, op in ipairs(ops) do
    r = r - op[1]
    if r <= 0 then return op end
  end
  return ops[#ops]
end

-- A canonical description of the project, from the views alone.
local function fmt(v)
  local t = type(v)
  if t == "number" then
    if v ~= v then return "nan" end
    return string.format("%.17g", v)
  elseif t == "table" then
    local keys = {}
    for k in pairs(v) do
      keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do
      out[#out + 1] = tostring(k) .. "=" .. fmt(v[k])
    end
    return "{" .. table.concat(out, ",") .. "}"
  end
  return tostring(v)
end
local function dump()
  local out = {}
  local p = api.project_get()
  -- Bookkeeping, not what the project holds: where it is saved, whether it
  -- changed since, and how many edits (undo and redo count) it has seen.
  p.path, p.modified, p.edits = nil, nil, nil
  out[#out + 1] = fmt(p)
  local list = api.track_list()
  list[#list + 1] = 0
  for _, t in ipairs(list) do
    local view = api.track_get(t)
    out[#out + 1] = fmt(view)
    for _, d in ipairs(view.devices) do
      local dv = api.device_get(d)
      dv.editor = nil
      out[#out + 1] = fmt(dv)
    end
    for _, c in ipairs(view.clips) do
      local cv = api.clip_get(c)
      out[#out + 1] = fmt(cv)
      if cv.kind == "midi" then out[#out + 1] = fmt(api.clip_notes(c)) end
    end
    for _, l in ipairs(api.lane_list(t)) do
      out[#out + 1] = fmt(l) .. fmt(api.lane_points(l.id))
    end
  end
  return table.concat(out, "\n")
end

local function first_difference(a, b)
  local la, lb = {}, {}
  for line in (a .. "\n"):gmatch("(.-)\n") do
    la[#la + 1] = line
  end
  for line in (b .. "\n"):gmatch("(.-)\n") do
    lb[#lb + 1] = line
  end
  for i = 1, math.max(#la, #lb) do
    if la[i] ~= lb[i] then return string.format("line %d:\n  before: %s\n  after:  %s", i, la[i], lb[i]) end
  end
  return "?"
end

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function check_views(step)
  stats.checks.views = stats.checks.views + 1
  local seen = {}
  local list = api.track_list()
  list[#list + 1] = 0
  for _, t in ipairs(list) do
    if seen[t] then fail(step, "views", "id " .. t .. " listed twice") end
    seen[t] = true
    local view = api.track_get(t)
    for _, kind in ipairs({ "devices", "clips" }) do
      for _, id in ipairs(view[kind]) do
        if seen[id] then fail(step, "views", "id " .. id .. " listed twice") end
        seen[id] = true
        local ok, err = pcall(kind == "devices" and api.device_get or api.clip_get, id)
        if not ok then fail(step, "views", kind .. " " .. id .. ": " .. tostring(err)) end
      end
    end
  end
end

local function check_undo(step)
  paw.flush()
  api.undo_checkpoint()
  local before = dump()
  if api.undo() then
    paw.flush()
    if not api.redo() then fail(step, "undo", "redo refused right after an undo") end
    paw.flush()
    local after = dump()
    if after ~= before then
      fail(step, "undo", "undo then redo changed the project: " .. first_difference(before, after))
    end
    stats.checks.undo = stats.checks.undo + 1
  end
end

--- Every file of a project folder, by its path in the folder, as one text.
local function folder(path)
  local out, pipe = {}, io.popen("cd '" .. path .. "' && find . -type f | LC_ALL=C sort")
  for name in pipe:lines() do
    out[#out + 1] = name .. "\n" .. (read(path .. "/" .. name) or "")
  end
  pipe:close()
  return table.concat(out, "\n")
end

local function check_save(step)
  local a, b = dir .. "/a", dir .. "/b"
  os.execute("rm -rf '" .. a .. "' '" .. b .. "'")
  local before = dump()
  api.project_save(a)
  local saved = dump()
  api.project_load(a)
  paw.flush()
  local loaded = dump()
  -- A clip file keeps notes in ticks: a note off the tick grid comes back
  -- on it. From the first load on, save and load change nothing.
  api.project_save(b)
  if folder(a) ~= folder(b) then fail(step, "save", "saving the loaded project gave different files") end
  api.project_load(b)
  paw.flush()
  local again = dump()
  if again ~= loaded then
    fail(step, "save", "a second load changed the project: " .. first_difference(loaded, again))
  end
  -- A project never named takes its folder's name when saved.
  before = before:gsub("name=untitled,", "name=a,", 1)
  if before ~= saved then
    -- Saving may only move recordings beside the file.
    if not before:find("recordings") then
      fail(step, "save", "saving changed the project: " .. first_difference(before, saved))
    end
  end
  stats.checks.save = stats.checks.save + 1
end

local function check_render(step)
  local length = api.project_get().length
  if length <= 0 then return end
  local opts = { start = 0, ["end"] = math.min(length, 16), tail = 0.2, bits = 32 }
  local a, b = dir .. "/r1.wav", dir .. "/r2.wav"
  local ok, info = pcall(api.render, a, opts)
  if not ok then
    if tostring(info):find("nothing to render") then return end
    fail(step, "render", tostring(info))
  end
  if info.nonfinite > 0 or info.peak ~= info.peak then fail(step, "render", "the render holds NaN or infinity") end
  -- The second time with every device run on every block: sleeping
  -- through silence changes nothing.
  opts.sleep = false
  api.render(b, opts)
  if read(a) ~= read(b) then fail(step, "render", "two renders of the same project differ, one with devices asleep") end
  stats.checks.render = stats.checks.render + 1
end

for step = 1, steps do
  local op = choose()
  stats.ops = stats.ops + 1
  local ok, err = pcall(op[3])
  if not ok then
    local msg = tostring(err)
    for _, bad in ipairs(BAD) do
      if msg:find(bad, 1, true) then fail(step, "error", op[2] .. ": " .. msg) end
    end
    stats.rejected = stats.rejected + 1
    local key = op[2] .. ": " .. msg:gsub("%d+", "N"):sub(1, 80)
    stats.errors[key] = (stats.errors[key] or 0) + 1
    if verbose then print(step, op[2], msg) end
  elseif verbose then
    print(step, op[2])
  end
  if chance(0.5) then
    paw.flush()
    api.undo_checkpoint()
  end
  if step % 7 == 0 then check_undo(step) end
  if step % 25 == 0 then check_views(step) end
  if step % 50 == 0 then check_save(step) end
  if step % 40 == 0 then check_render(step) end
end

api.transport_stop()
local kinds = 0
for _ in pairs(stats.errors) do
  kinds = kinds + 1
end
B.emit({
  workload = "fuzz",
  seed = seed,
  steps = steps,
  ops = stats.ops,
  rejected = stats.rejected,
  rejection_kinds = kinds,
  undo_checks = stats.checks.undo,
  save_checks = stats.checks.save,
  render_checks = stats.checks.render,
  view_checks = stats.checks.views,
  failed = false,
})
if verbose then
  for k, n in pairs(stats.errors) do
    print(n, k)
  end
end
os.execute("rm -rf '" .. dir .. "'")
api.quit(0)
