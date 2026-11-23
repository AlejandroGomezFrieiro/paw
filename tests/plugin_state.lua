-- A plugin's saved state goes back into it, in each format: in a
-- snapshot, on a state lane in a render, and through undo and redo. After
-- a load the state is the truth: what the plugin tells of its parameters
-- then is not an edit. Loaded by tests/suite.lua with its helpers; needs
-- the dev shell's test plugins (`tests/tools/suite.sh plugins`).
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

local function kind_of(format, pattern)
  for _, info in ipairs(paw.device_types()) do
    if info.format == format and info.name:find(pattern) then return info.kind end
  end
end

local keys = T.keys

--- Surge XT in each format that the test plugins have.
local function surges()
  local out = {}
  for _, format in ipairs({ "clap", "vst3", "lv2" }) do
    local kind = kind_of(format, "^Surge XT$")
    if kind then out[#out + 1] = kind end
  end
  return out
end

--- A track that holds A3 for `beats` through `kind`, with the cursor and
--- the device panel on the device.
local function instrument(kind, beats)
  local track = paw.add_track({ name = kind })
  -- A note for each four beats: a state load can end the notes that sound.
  local notes = {}
  for at = 0, beats - 1, 4 do
    notes[#notes + 1] = { pitch = "A3", start = at, length = 4 }
  end
  track:add_clip({ start = 0, length = beats, notes = notes })
  local d = track:add_device(kind)
  paw.flush()
  paw.cursor.set_track(track.id)
  paw.ui.focus("devices")
  paw.fx.select(d.id)
  api.undo_checkpoint()
  return d
end

--- The pitch of a render, from `from` to `to` seconds.
local function pitch(from, to) return T.frequency(T.render({ tail = 0, bits = 16 }), from or 0.5, to or 1.5) end

local function has_param(d, key)
  for _, p in ipairs(api.device_get(d.id).param_info) do
    if p.key == key then return true end
  end
end

--- The octave of scene A as the plugin holds it, -3 to 3: as its
--- parameter tells (CLAP, VST3), else as its saved state does (Surge XT's
--- LV2 has no parameters).
local function octave(d)
  if has_param(d, "a_octave") then return math.floor(api.device_param(d.id, "a_octave").value * 6 - 3 + 0.5) end
  return tonumber(require("plugstate").slot(d.id, "octave").value)
end

--- Wait until the plugin's own state (not the project's) holds `want` as
--- the octave. A plugin that takes a state on in its next block (Surge
--- XT) tells its new values only after that block.
local function holds(d, want)
  paw.flush()
  T.until_(function() return octave(d) == want end, "the octave " .. want .. " in the plugin")
end

--- Wait until the plugin sleeps (its note ended and its tail went by), so
--- that a state reaches a plugin at rest. Surge XT as a CLAP plugin never
--- says it may sleep: then, after three seconds, the state reaches it
--- awake, which it must take as well.
local function rested()
  local before, deadline = api.engine_get().device_sleeps, api.now() + 3000
  while api.engine_get().device_sleeps <= before + 10 and api.now() < deadline do
    paw.wait(20)
  end
end

--- The parameters that the project itself sets for a device (not the
--- values that the plugin reports), as the current undo step holds them.
local function own(d)
  if not has_param(d, "a_volume") then return { a_volume = 0.75 } end
  for _, track in ipairs(api.undo_project().tracks) do
    for _, device in ipairs(track.devices or {}) do
      if device.id == d.id then return device.params or {} end
    end
  end
end

local touched = 0
paw.on("param.touched", function(e)
  if e.from == "editor" then touched = touched + 1 end
end)

test("a plugin takes a snapshot back at rest, and the echo of its values is no edit (each format)", function()
  local kinds = surges()
  if #kinds == 0 then return "skipped: Surge XT not found" end
  paw.ext.load("extensions/plugstate")
  for _, kind in ipairs(kinds) do
    fresh()
    local d = instrument(kind, 4)
    -- The project sets one parameter: the snapshots keep it.
    if has_param(d, "a_volume") then api.device_set_param(d.id, "a_volume", 0.75) end
    api.undo_checkpoint()
    keys("\\s")
    keys(":plugstate.load slot=octave 1<CR>")
    holds(d, 1)
    eq(octave(d), 1, kind .. ": an octave up")
    -- A preset of plugstate sets the state alone: the parameter again.
    if has_param(d, "a_volume") then api.device_set_param(d.id, "a_volume", 0.75) end
    api.undo_checkpoint()
    keys("\\s")
    T.near(pitch(), 440, 10, kind .. ": B plays an octave higher")
    T.near(own(d).a_volume, 0.75, 1e-6, kind .. ": the project's own parameter stays")
    local step = api.undo_current()
    touched = 0

    -- Back to A with the plugin at rest.
    rested()
    keys("[v")
    holds(d, 0)
    eq(octave(d), 0, kind .. ": A is back in the plugin")
    T.near(pitch(), 220, 6, kind .. ": A plays A3")
    eq(api.undo_current(), step + 1, kind .. ": one step for the recall")
    api.wait(300)
    T.near(own(d).a_volume or -1, 0.75, 1e-6, kind .. ": the echo of the state takes nothing from the project")

    rested()
    keys("u")
    holds(d, 1)
    eq(octave(d), 1, kind .. ": u gives B back to the plugin")
    T.near(pitch(), 440, 10, kind .. ": and B plays")
    eq(api.undo_current(), step, kind .. ": u goes back one step")

    keys("<C-r>")
    holds(d, 0)
    eq(octave(d), 0, kind .. ": <C-r> gives A again")
    T.near(pitch(), 220, 6, kind .. ": and A plays")
    eq(api.undo_current(), step + 1, kind .. ": <C-r> goes forward one step")
    api.wait(300)
    paw.flush()
    eq(api.undo_current(), step + 1, kind .. ": the echo makes no step of its own")
    eq(api.undo_pending(), false, kind .. ": nor an open one")
    eq(touched, 0, kind .. ": and no move of a parameter in the plugin's window")
    T.near(own(d).a_volume or -1, 0.75, 1e-6, kind .. ": the project's parameter is still there")
  end
end)

test("a state lane gives each format of a plugin its saved state at the point, in a render", function()
  local kinds = surges()
  if #kinds == 0 then return "skipped: Surge XT not found" end
  paw.ext.load("extensions/plugstate")
  local plugstate = require("plugstate")
  for _, kind in ipairs(kinds) do
    fresh()
    local d = instrument(kind, 8)
    keys("\\s")
    keys(":plugstate.load slot=octave 1<CR>")
    holds(d, 1)
    keys("\\s")
    rested()
    plugstate.lane_point(d.id, 0, plugstate.lane_snapshot(d.id, "A"))
    -- Before the next note: Surge XT takes a whole state on at the start
    -- of its next block, and ends the notes that sound then, also one
    -- that starts in that block.
    plugstate.lane_point(d.id, 3.5, plugstate.lane_snapshot(d.id, "B"))
    api.undo_checkpoint()
    local info = T.render({ tail = 0, bits = 16 })
    T.near(T.frequency(info, 0.25, 1.6), 220, 6, kind .. ": A before the point")
    T.near(T.frequency(info, 2.2, 3.8), 440, 10, kind .. ": B after it")
  end
end)

--- Wait until no device runs a block for 300 ms: all of them sleep. False
--- after `seconds`.
local function all_asleep(seconds)
  local runs, still = api.engine_get().device_runs, 0
  for _ = 1, seconds * 50 do
    api.sleep(20)
    local now = api.engine_get().device_runs
    still = now == runs and still + 1 or 0
    runs = now
    if still >= 15 then return true end
  end
  return false
end

test("an LV2 plugin sleeps once its tail went by in silence, and a note or a parameter wakes it", function()
  local surge = kind_of("lv2", "^Surge XT$")
  local limiter = kind_of("lv2", "Limiter Stereo$")
  if not surge or not limiter then return "skipped: test plugins not found" end
  fresh()
  -- A note, sixteen beats of silence (eight seconds: longer than the five
  -- seconds an LV2 plugin is given to ring), and a note again.
  local track = paw.add_track({ name = "lv2" })
  track:add_clip({
    start = 0,
    length = 24,
    notes = {
      { pitch = "A3", start = 0, length = 1 },
      { pitch = "A3", start = 20, length = 1 },
    },
  })
  track:add_device(surge)
  paw.flush()
  local awake = T.render({ tail = 0, sleep = false, bits = 16 })
  eq(awake.device_sleeps, 0, "with sleep off, the plugin runs each block")
  local asleep = T.render({ tail = 0, sleep = true, bits = 16 })
  eq(asleep.device_sleeps > 0, true, "it sleeps through the silence: " .. asleep.device_sleeps .. " blocks")
  eq(asleep.device_runs < awake.device_runs, true, "and runs fewer blocks")
  T.near(T.frequency(asleep, 10.1, 10.4), T.frequency(awake, 10.1, 10.4), 10, "the note after the silence wakes it")
  T.near(T.channel_peaks(asleep, 10, 10.5), T.channel_peaks(awake, 10, 10.5), 0.05, "and sounds as loud")
  eq(T.channel_peaks(asleep, 10, 10.5) > 0.05, true, "which is heard")

  -- Live and stopped: an effect with a latency sleeps too, and a
  -- parameter wakes it.
  fresh()
  local fx = paw.add_track({ name = "fx" })
  fx:add_device("synth")
  local d = fx:add_device(limiter)
  paw.flush()
  eq(all_asleep(8), true, "stopped and silent, the LV2 effect sleeps after its tail")
  local runs = api.engine_get().device_runs
  local gain
  for _, p in ipairs(api.device_get(d.id).param_info) do
    if p.key == "output_gain" or p.key == "g_out" then gain = p end
  end
  api.device_set_param(d.id, gain.key, gain.min)
  paw.flush()
  for _ = 1, 50 do
    if api.engine_get().device_runs > runs then break end
    api.sleep(20)
  end
  eq(api.engine_get().device_runs > runs, true, "a parameter wakes it")
end)

test("a state given while the engine rests reaches a plugin that takes it on in its next block", function()
  local built = os.getenv("PAW_TEST_STUB") or "target/release/examples/libstub_clap.so"
  if not io.open(built) then return "skipped: `cargo test -p paw-plugins` builds the test plugin" end
  fresh()
  local dir = T.scratch .. "/stub-rest"
  os.execute("mkdir -p '" .. dir .. "' && cp '" .. built .. "' '" .. dir .. "/stub.clap'")
  paw.plugins.add_dir(dir, "stubs")
  T.after(function() paw.plugins.remove_dir(dir) end)
  local d = paw.add_track({ name = "Stub" }):add_device("clap:dev.paw.stub")
  paw.flush()
  api.undo_checkpoint()
  -- Stopped, with nothing that sounds: the stub sleeps, then the engine.
  local rests = api.engine_get().engine_rests
  T.until_(function() return api.engine_get().engine_rests > rests end, "the engine to rest")
  -- The stub takes the state (23) on at the start of its next block.
  api.device_load(d.id, { state = "FwAAAA==" })
  T.until_(function() return api.device_state(d.id) == "FwAAAA==" end, "the stub to take the state on")
end)

test("a plugin that asks for a block while the engine rests gets its next block", function()
  local built = os.getenv("PAW_TEST_STUB") or "target/release/examples/libstub_clap.so"
  if not io.open(built) then return "skipped: `cargo test -p paw-plugins` builds the test plugin" end
  fresh()
  local dir = T.scratch .. "/stub-wake"
  os.execute("mkdir -p '" .. dir .. "' && cp '" .. built .. "' '" .. dir .. "/stub.clap'")
  paw.plugins.add_dir(dir, "stubs")
  T.after(function() paw.plugins.remove_dir(dir) end)
  local d = paw.add_track({ name = "Stub" }):add_device("clap:dev.paw.stub")
  paw.flush()
  local rests = api.engine_get().engine_rests
  T.until_(function() return api.engine_get().engine_rests > rests end, "the engine to rest")
  local runs = api.engine_get().device_runs
  -- The stub changes by itself and asks the host for a block.
  api.device_call(d.id, "stub.tell", "5")
  T.until_(function() return api.engine_get().device_runs > runs end, "the stub to run a block")
end)

test("a move in a plugin's window right after a state is an edit, and the echo of the state is not", function()
  local built = os.getenv("PAW_TEST_STUB") or "target/release/examples/libstub_clap.so"
  if not io.open(built) then return "skipped: `cargo test -p paw-plugins` builds the test plugin" end
  fresh()
  local dir = T.scratch .. "/stub-echo"
  os.execute("mkdir -p '" .. dir .. "' && cp '" .. built .. "' '" .. dir .. "/stub.clap'")
  paw.plugins.add_dir(dir, "stubs")
  T.after(function() paw.plugins.remove_dir(dir) end)
  local d = paw.add_track({ name = "Stub" }):add_device("clap:dev.paw.stub")
  paw.flush()
  api.undo_checkpoint()
  local moves = {}
  local handler = paw.on("param.touched", function(e)
    if e.device == d.id and e.from == "editor" then moves[#moves + 1] = e.value end
  end)
  local function settle()
    for _ = 1, 100 do
      paw.flush()
      if #moves > 0 then break end
      api.wait(20)
    end
    api.wait(100)
  end
  -- The stub takes the state (7) on in its next block and tells of it
  -- with no gesture; the move to 9 comes in the same block, in a gesture.
  api.device_load(d.id, { state = "BwAAAA==" })
  api.device_call(d.id, "stub.move", "9")
  settle()
  eq(#moves, 1, "the move is an edit, the echo is not")
  T.near(moves[1], 9, 1e-6, "the move's value")
  -- An echo of the state that comes a second late, on a slow computer, is
  -- still no edit.
  api.device_load(d.id, { state = "BwAAAA==" })
  api.wait(1000)
  api.device_call(d.id, "stub.tell", "7")
  settle()
  paw.off(handler)
  eq(#moves, 1, "the late echo is no edit")
end)
