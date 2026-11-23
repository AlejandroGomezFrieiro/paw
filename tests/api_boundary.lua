-- The boundary of `paw.api` as a whole: each kernel function, called with
-- wrong arguments, gives a Lua error or a documented result. No call
-- panics, ends the program or changes the project without an undo step.
--
-- The walk calls every function that `paw.api` has, so a new function is
-- called too. It reads the names and types of the arguments from the Rust
-- source, as tools/apidoc.lua does, and makes each argument wrong in turn:
-- no arguments, another type, a negative and a huge number, the id of
-- something deleted, a long string, a string with a NUL in it.
local T = ...
local paw = require("paw")
local api = paw.api

-- The functions that the walk does not call, each with the reason.
local NOT_CALLED = {
  quit = "ends the program",
  reload = "loads the runtime again, and this test with it",
  sleep = "waits as long as it is told: a huge time waits for ever",
  wait = "waits as long as it is told: a huge time waits for ever",
  test_panic = "panics on purpose: the test below calls it",
  limit_hook = "replaces the hook of paw.limit, which the test cannot put back",
  engine_restart = "opens the audio device that it is given, which can be one of the machine",
  audio_use = "opens an audio device of the machine",
  audio_reconnect = "opens an audio device of the machine again",
  audio_devices = "lists the audio devices of the machine",
  audio_watch = "changes how paw watches the audio device, which the test cannot read back",
  midi_inputs = "lists the MIDI ports of the machine",
  midi_outputs = "lists the MIDI ports of the machine",
  midi_open_port = "opens a MIDI port of the machine",
  midi_open_output = "opens a MIDI port of the machine",
  midi_select = "selects the MIDI ports of the machine that paw hears",
  proc_spawn = "starts a program of the machine",
  which = "looks for a program in the PATH of the machine",
}

-- What a call with a good value changes outside the project, and how the
-- test puts it back. `restore(result, args)` runs after each call that did
-- not fail.
local seats = require("paw.seats")
-- What the walk found before it started.
local saved = {}
local SHAPES = {
  ui_caps_set = { restore = function() api.ui_caps_set(saved.caps) end },
  load_apart = { restore = function() api.load_apart(saved.apart) end },
  ui_seat = { restore = function() api.ui_seat(seats.current) end },
  engine_set_threads = { restore = function() api.engine_set_threads(paw.opt.threads) end },
  engine_set_sleep = { restore = function() api.engine_set_sleep(paw.opt.device_sleep) end },
  undo_limits = {
    restore = function() api.undo_limits(paw.opt.undo_steps, math.floor(paw.opt.undo_memory * 1024 * 1024)) end,
  },
  ui_mouse = { restore = function() api.ui_mouse(paw.opt.mouse ~= false) end },
  preview_level = { restore = function() api.preview_level(paw.opt.audition_level) end },
  engine_follow = { restore = function() api.engine_follow(nil) end },
  engine_follow_always = { restore = function() api.engine_follow_always(nil) end },
  limit_watch = { restore = function() api.limit_watch(nil) end },
  audio_test_device = { restore = function() api.audio_test_device({}) end },
  midi_test_ports = { restore = function() api.midi_test_ports({}) end },
  timer_start = { restore = function(id) api.timer_stop(id) end },
  sock_listen = { restore = function(id) api.sock_close(id) end },
  measure_start = { restore = function(id) api.measure_cancel(id) end },
  engine_hold = { restore = function(_, args) api.engine_hold(args[1], nil) end },
  -- Each folder that the call took, also one that is not there.
  plugins_add_dir = {
    restore = function(found, args) api.plugins_remove_dir(args[1], found and found.kinds or {}) end,
  },
}
-- The ones whose good value is a name or a folder that the test gives.
for name, remove in pairs({
  engine_midi_filter = function(key) api.engine_midi_filter(key, nil) end,
  clip_kind_define = api.clip_kind_remove,
  lua_devices_add = api.lua_devices_remove,
  state_set = function(key) api.state_set(key, nil) end,
}) do
  SHAPES[name] = { restore = function() remove(T.scratch .. "/boundary") end }
end

local function first_line(text) return (tostring(text):match("^[^\n]*")) end

-- The fixture: one of each thing that an id names, and the ids of things
-- that were there and are deleted.
local function fixture()
  T.fresh()
  local track = paw.add_track({ name = "Boundary" })
  local clip = track:add_clip({ start = 0, length = 4 })
  clip:add_note({ pitch = 60, start = 0, length = 1 })
  local device = track:add_device("synth")
  local lane = api.lane_add(track.id, { target = "volume", points = { { 0, -6 }, { 4, 0 } } })
  local gone = paw.add_track({ name = "Gone" })
  local gone_clip = gone:add_clip({ start = 0, length = 4 })
  local ids = {
    track = track.id,
    clip = clip.id,
    device = device.id,
    lane = lane,
    gone_track = gone.id,
    gone_clip = gone_clip.id,
  }
  api.track_remove(gone.id)
  paw.flush()
  api.undo_checkpoint()
  return ids
end

local NUMBER = {
  Id = true,
  u64 = true,
  i64 = true,
  u32 = true,
  i32 = true,
  usize = true,
  u8 = true,
  u16 = true,
  f64 = true,
  f32 = true,
}

-- The class of an argument from its Rust type, and whether nil is a good
-- value of it.
local function class_of(rust)
  rust = (rust or "LuaValue"):gsub("^%s+", ""):gsub("%s+$", "")
  local inner = rust:match("^Option<(.*)>$")
  if inner then return class_of(inner), true end
  if rust:match("^Vec<") then return "list" end
  if NUMBER[rust] then return "number" end
  if rust == "String" then return "path" end
  if rust == "LuaString" or rust == "LuaText" then return "text" end
  if rust == "bool" then return "boolean" end
  if rust == "Table" then return "table" end
  if rust == "Function" then return "function" end
  return "value"
end

-- What an id argument names, from its name or else from the start of the
-- function's name (`clip_get(id)`).
local function id_kind(fname, param)
  local kind = param == "id" and fname:match("^(%a+)_") or param
  if kind == "track" or kind == "clip" or kind == "device" or kind == "lane" then return kind end
end

-- A good value of an argument, for the positions that a call does not make
-- wrong: then the call gets past its first check. A path is in the scratch
-- folder of the test.
local function good(fname, param, rust, ids)
  local class, optional = class_of(rust)
  if optional then return nil end
  if class == "number" then return ids[id_kind(fname, param)] or 0 end
  if class == "path" then return T.scratch .. "/boundary" end
  if class == "text" then return "x" end
  if class == "boolean" then return true end
  if class == "table" or class == "list" then return {} end
  if class == "function" then
    return function() end
  end
  return nil
end

local LONG = string.rep("x", 70000)

-- The wrong values of an argument: of another type, out of range, and the id
-- of something deleted.
local function wrong(fname, param, rust, ids)
  local class = class_of(rust)
  if class == "number" then
    local out = { "abc", {}, true, -1, 0 / 0, 1e300, -1e300, math.huge, 2 ^ 31, 2 ^ 53 }
    local kind = id_kind(fname, param)
    local gone = kind and ids["gone_" .. kind]
    if gone then out[#out + 1] = gone end
    return out
  elseif class == "path" then
    return { {}, true, "", T.scratch .. "/" .. LONG, T.scratch .. "/a\0b" }
  elseif class == "text" then
    return { {}, true, LONG, "a\0b", "\255\254" }
  elseif class == "boolean" then
    return { "abc", {} }
  elseif class == "table" then
    return { 1, "abc", true, { x = { y = 1e300 } }, { -1, 0 / 0 } }
  elseif class == "function" then
    return { 1, "abc", {} }
  elseif class == "list" then
    return { 1, "abc", { "abc" }, { {} }, { -1, 1e300 } }
  end
  return { 1, -1, 1e300, 0 / 0, "abc", true, LONG, { x = { y = 1e300 } }, { 1, 2, 3 }, print }
end

-- The song as the walk compares it before and after a call: each track,
-- clip, note, lane and the tempo. Not where it is saved, nor whether it is.
local function fingerprint()
  local project = api.project_get()
  project.path, project.modified = nil, nil
  local parts = { project, api.tempo_points(), api.nest_list() }
  for _, track in ipairs(api.track_list({})) do
    parts[#parts + 1] = api.track_get(track)
    for _, clip in ipairs(api.clip_list(track)) do
      parts[#parts + 1] = clip
      parts[#parts + 1] = api.clip_notes(clip.id)
    end
    for _, lane in ipairs(api.lane_list(track)) do
      parts[#parts + 1] = lane
      parts[#parts + 1] = api.lane_points(lane.id)
    end
  end
  return api.json_encode(parts)
end

-- One call of `paw.api.<name>`: what is wrong with it, or nil. A panic in
-- Rust comes back as an error that names the function (`guarded!` in
-- crates/paw-core/src/api/mod.rs).
local function check(name, args, n)
  api.undo_checkpoint()
  local before, step = fingerprint(), api.undo_current()
  local ok, result = pcall(api[name], unpack(args, 1, n))
  if fingerprint() ~= before and not api.undo_pending() and api.undo_current() == step then
    return "changed the project without an undo step", ok, result
  end
  if ok then return nil, ok, result end
  local text = first_line(result)
  if text:find("stopped on a bug in paw", 1, true) then return "panicked: " .. text, ok, result end
  if text:find("^bad argument") and not text:find("`paw.api." .. name .. "`", 1, true) then
    return "gave an error that does not name the function: " .. text, ok, result
  end
  return nil, ok, result
end

local function show(value)
  if type(value) == "string" and #value > 40 then return string.format("<a string of %d bytes>", #value) end
  return (paw.inspect(value):gsub("%s+", " "))
end

-- Put back what a call can change outside the project.
local function settle(name, args, ok, result)
  paw.transport.stop()
  api.preview_stop()
  api.render_cancel()
  if api.trial_active() then api.trial_end(false) end
  local restore = SHAPES[name] and SHAPES[name].restore
  if ok and restore then restore(result, args) end
end

-- The calls of one function: none of its arguments, then each argument wrong
-- in turn with good values in the others. Gives the problems and the count.
local function walk(name, entry, problems)
  local ids = fixture()
  local n = #entry.params
  local base = {}
  for i, param in ipairs(entry.params) do
    base[i] = good(name, param, entry.types[i], ids)
  end
  local calls = { {} }
  for i, param in ipairs(entry.params) do
    for _, value in ipairs(wrong(name, param, entry.types[i], ids)) do
      local args = { unpack(base, 1, n) }
      args[i] = value
      calls[#calls + 1] = args
    end
  end
  for _, args in ipairs(calls) do
    local problem, ok, result = check(name, args, n)
    if problem then
      local shown = {}
      for i = 1, n do
        shown[i] = show(args[i])
      end
      problems[#problems + 1] = string.format("paw.api.%s(%s) %s", name, table.concat(shown, ", "), problem)
    end
    settle(name, args, ok, result)
  end
  return #calls
end

T.test("each paw.api function given wrong arguments gives an error that names it, and no crash", function()
  saved.caps, saved.apart = api.ui_caps(), api.load_apart(false)
  api.load_apart(saved.apart)
  local said = #paw.ui.messages
  T.after(function()
    -- What the calls said: the list of messages keeps 500 at most, and
    -- tests after this one count what is added to it.
    for i = #paw.ui.messages, said + 1, -1 do
      paw.ui.messages[i] = nil
    end
    T.fresh()
  end)
  local kernel = assert(loadfile("tools/apidoc.lua"))("module").kernel_functions()
  local names = {}
  for name, fn in pairs(api) do
    if type(fn) == "function" and not NOT_CALLED[name] then names[#names + 1] = name end
  end
  table.sort(names)
  local problems, calls = {}, 0
  for _, name in ipairs(names) do
    -- A function that the source does not show (one that the runtime adds
    -- in Lua) gets three arguments of any type.
    local entry = kernel[name] or { params = { "a", "b", "c" }, types = {} }
    calls = calls + walk(name, entry, problems)
  end
  T.eq(#names > 300, true, "the walk finds the functions: " .. #names)
  T.eq(table.concat(problems, "\n"), "", #problems .. " of " .. calls .. " calls")
end)

T.test("a panic in a paw.api function fails the walk with the name of the function", function()
  local problem = check("test_panic", { "a bug for the test", true }, 2)
  T.eq(
    problem,
    "panicked: runtime error: paw.api.test_panic stopped on a bug in paw: a bug for the test",
    "the problem"
  )
end)

T.test("saving the project to an empty path is refused, and writes nothing in the current folder", function()
  fixture()
  T.fails(function() api.project_save("") end, "a project needs a path to save to, not an empty one", 'save to ""')
  T.eq(api.project_get("path"), nil, "the project has no file still")
end)

T.test("the functions that the paw.api walk does not call or restores are functions of paw.api", function()
  local gone = {}
  for _, list in ipairs({ NOT_CALLED, SHAPES }) do
    for name in pairs(list) do
      if type(api[name]) ~= "function" then gone[#gone + 1] = name end
    end
  end
  table.sort(gone)
  T.eq(table.concat(gone, " "), "", "names to take out of NOT_CALLED and SHAPES")
end)
