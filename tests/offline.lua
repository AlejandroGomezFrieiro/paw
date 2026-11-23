-- Plugins that load apart from the main loop, plugins that are not installed
-- or set offline, and an audio device that goes away and comes back.
local T = ...
local test, eq, fails, fresh, render = T.test, T.eq, T.fails, T.fresh, T.render
local api = paw.api

local function plugin_kind(format, pattern)
  for _, info in ipairs(paw.device_types()) do
    if info.format == format and info.name:find(pattern) then return info.kind end
  end
end

--- A plugin that runs in a helper process, or nil where there is none.
local function sandboxed_limiter()
  if os.getenv("PAW_PLUGIN_SANDBOX") == "0" then return nil end
  for _, format in ipairs({ "clap", "lv2", "vst3" }) do
    local kind = plugin_kind(format, "Limiter Stereo$")
    if kind then return kind end
  end
end

--- Run `fn` with plugins made apart, as the program does when it has a UI.
local function apart(fn)
  local was = api.load_apart(true)
  local ok, err = xpcall(fn, debug.traceback)
  api.load_apart(was)
  if not ok then error(err, 0) end
  return err
end

--- Make the plugin of a device that has not started to load hang while it
--- is made, until the session gives up on it: at once, as a test does not
--- wait for the limit of a real plugin.
local function hang_while_made(fx)
  api.device_call(fx.id, "sandbox.hang")
  api.device_call(fx.id, "sandbox.deadline", "1")
end

--- The saved state of every device in a project file, by kind.
local function saved_states(path)
  local file = api.json_decode(T.read_file(path))
  local out = {}
  for _, track in ipairs(file.project.tracks) do
    for _, device in ipairs(track.devices) do
      out[#out + 1] = device.state or false
    end
  end
  return out
end

--- A project with a limiter whose output is turned all the way down, saved;
--- returns its path, the kind, the parameter, and the state as saved.
local function saved_limiter(kind, name)
  fresh()
  local t = T.tone("tone", 2)
  local fx = t:add_device(kind)
  local gain
  for _, p in ipairs(fx:get().param_info) do
    if p.key == "output_gain" or p.key == "g_out" then gain = p end
  end
  fx:set(gain.key, gain.min)
  -- The plugin takes the value with its next block; its saved state after.
  -- A wait of schedule time does not run the plugin's blocks (they run on
  -- the wall clock): wait for a block of the device itself.
  T.next_block(1, fx.id)
  local path = paw.project.save(T.scratch .. "/" .. name .. ".json")
  return path, gain, saved_states(path)[2]
end

test("a plugin added with loading apart is there at once and comes in when made", function()
  local kind = sandboxed_limiter()
  if not kind then return "skipped: test plugins not found" end
  return apart(function()
    fresh()
    local t = T.tone("tone", 2)
    local ready = {}
    local handler = paw.on("device.ready", function(e) ready[#ready + 1] = e end)
    local fx = t:add_device(kind)
    -- Slow to make: the test holds it back, and the program does not wait for it.
    api.device_call(fx.id, "sandbox.hold")
    T.settle()
    eq(fx:get().status, "loading", "adding it returns while the plugin is made")
    paw.cursor.set_track(t)
    local devices = paw.frontend.state(-1).devices
    eq(devices[#devices].status, "loading", "and the frontend's state says so")
    eq(#ready, 0, "it is not ready while it is held")
    api.device_call(fx.id, "sandbox.release")
    T.until_(function() return #ready > 0 end, "the plugin to be made")
    paw.off(handler)
    eq(ready[1].id, fx.id, "device.ready names it")
    local d = fx:get()
    eq(d.status, "running", "running now")
    eq(#d.param_info > 10, true, "with its parameters")
  end)
end)

test("six plugins that load at the same time are all made", function()
  local kind = sandboxed_limiter()
  if not kind then return "skipped: test plugins not found" end
  return apart(function()
    fresh()
    local t = paw.add_track()
    local list = {}
    for i = 1, 6 do
      list[i] = t:add_device(kind)
      api.device_call(list[i].id, "sandbox.hold")
    end
    T.settle()
    for i, fx in ipairs(list) do
      eq(fx:get().status, "loading", "plugin " .. i .. " loads while the others do")
    end
    for _, fx in ipairs(list) do
      api.device_call(fx.id, "sandbox.release")
    end
    T.until_(function()
      for _, fx in ipairs(list) do
        if fx:get().status ~= "running" then return false end
      end
      return true
    end, "the six plugins to be made")
  end)
end)

test("a plugin that hangs while it is made is stopped and keeps its saved state", function()
  local kind = sandboxed_limiter()
  if not kind then return "skipped: test plugins not found" end
  local path, gain, state = saved_limiter(kind, "hang")
  eq(type(state), "string", "the plugin has a saved state")
  return apart(function()
    local stopped = {}
    local handler = paw.on("device.stopped", function(e) stopped[#stopped + 1] = e end)
    fresh()
    paw.project.load(path)
    local fx = paw.tracks()[1]:devices()[2]
    hang_while_made(fx)
    eq(fx:get().status, "loading", "opening does not wait for the plugin")
    -- Saving now writes back what the file had, not an empty state.
    local during = paw.project.save(T.scratch .. "/hang-during.json")
    eq(saved_states(during)[2], state, "saved while loading: the state is kept")
    T.until_(function() return #stopped > 0 end, "the plugin that hangs to be given up on")
    paw.off(handler)
    eq(stopped[1].device, fx.id, "device.stopped names it")
    eq(stopped[1].loading, true, "while it was loading")
    eq(stopped[1].reason:find("did not answer") ~= nil, true, "and says why: " .. stopped[1].reason)
    local d = fx:get()
    eq(d.status, "stopped", "the device is stopped")
    local after = paw.project.save(T.scratch .. "/hang-after.json")
    eq(saved_states(after)[2], state, "saved when stopped: the state is kept")
    fails(function() render({ tail = 0 }) end, "did not load", "rendering with a plugin that did not load")
    -- Once the plugin behaves, a restart brings it in with its state.
    fx:restart()
    eq(fx:get().status ~= "stopped", true, "restarting starts it again")
    T.until_(function() return fx:get().status == "running" end, "the plugin to be made again")
    eq(fx.params[gain.key], gain.min, "with what the project had of it")
    eq(saved_states(paw.project.save(T.scratch .. "/hang-restarted.json"))[2] ~= nil, true, "it saves a state again")
  end)
end)

test("rendering waits for plugins that are still loading", function()
  local kind = sandboxed_limiter()
  if not kind then return "skipped: test plugins not found" end
  local path = saved_limiter(kind, "render-wait")
  local quiet = render({ tail = 0.2 }).peak
  return apart(function()
    fresh()
    paw.project.load(path)
    local fx = paw.tracks()[1]:devices()[2]
    -- Slow to make: held until the render starts.
    api.device_call(fx.id, "sandbox.hold")
    T.settle()
    eq(fx:get().status, "loading", "loading when the render starts")
    api.device_call(fx.id, "sandbox.release")
    local info = render({ tail = 0.2 })
    eq(info.peak <= quiet + 1e-6, true, "the render has the plugin in it")
  end)
end)

-- Plugins that are not installed ----------------------------------------------

--- Write a project file holding one track with `devices`, and return its path.
local function project_with(name, devices)
  local path = T.scratch .. "/" .. name .. ".json"
  fresh()
  local t = paw.add_track({ name = "Keys" })
  for _, d in ipairs(devices) do
    t:add_device(d.kind, d.params)
  end
  paw.project.save(path)
  return path
end

--- Change a project file's text, and return it.
local function rewrite(path, from, to)
  local text = T.read_file(path)
  local changed = text:gsub(from, to)
  T.write_file(path, changed)
  return changed
end

test("a plugin that is not installed is kept as it was: named, passed over, saved unchanged", function()
  local path = project_with("missing", { { kind = "gain", params = { gain = -6 } } })
  -- As if it were a plugin, with a state and a name, that this machine lacks.
  rewrite(path, '"kind": "gain"', '"kind": "clap:com.example.gone", "name": "Gone Synth", "state": "AAEC"')
  rewrite(path, '"gain": %-6%.0', '"cutoff": 0.25')
  local before = api.json_decode(T.read_file(path)).project.tracks[1].devices[1]
  fresh()
  paw.project.load(path)
  local device = paw.tracks()[1]:devices()[1]
  local d = device:get()
  eq(d.status, "missing", "the device is marked missing")
  eq(d.name, "Gone Synth", "with the plugin's name")
  eq(d.kind, "clap:com.example.gone", "and its id")
  eq(d.params.cutoff, 0.25, "it holds its parameter values")
  fails(function() device:restart() end, "not installed", "restarting a plugin that is not there")
  paw.cursor.set_track(paw.tracks()[1])
  local devices = paw.frontend.state(-1).devices
  eq(devices[1].status, "missing", "the frontend's state says so")
  local saved = paw.project.save(T.scratch .. "/missing-saved.json")
  local after = api.json_decode(T.read_file(saved)).project.tracks[1].devices[1]
  eq(after.state, before.state, "its state is written back unchanged")
  eq(after.name, before.name, "and its name")
  eq(after.params.cutoff, 0.25, "and its parameters")
end)

test("a plugin that was missing is the real plugin again when it is found", function()
  local kind = sandboxed_limiter()
  if not kind then return "skipped: test plugins not found" end
  local path, gain, state = saved_limiter(kind, "found-again")
  local quiet = render({ tail = 0.2 }).peak
  local real = kind:gsub("%p", "%%%0")
  rewrite(path, real, "clap:com.example.not-here")
  fresh()
  paw.project.load(path)
  eq(paw.tracks()[1]:devices()[2]:get().status, "missing", "missing while it is not found")
  local dry = render({ tail = 0.2 }).peak
  eq(dry > quiet * 5, true, "and passed over")
  paw.project.save(path)
  eq(saved_states(path)[2], state, "saved unchanged")
  -- Installed again (here: named again), the next open finds it.
  rewrite(path, "clap:com%.example%.not%-here", (kind:gsub("%%", "%%%%")))
  fresh()
  paw.project.load(path)
  local fx = paw.tracks()[1]:devices()[2]
  eq(fx:get().status, "running", "the real plugin runs")
  eq(fx.params[gain.key], gain.min, "with its parameter")
  eq(render({ tail = 0.2 }).peak <= quiet + 1e-6, true, "and its sound")
end)

-- Offline devices --------------------------------------------------------------

test("a device set offline is not made, is passed over, keeps its state, and comes back", function()
  local kind = sandboxed_limiter()
  if not kind then return "skipped: test plugins not found" end
  local path, gain, state = saved_limiter(kind, "offline")
  local quiet = render({ tail = 0.2 }).peak
  local fx = paw.tracks()[1]:devices()[2]
  local pid = tonumber((select(2, pcall(api.device_call, fx.id, "sandbox.pid"))))
  fx:set_offline(true)
  local d = fx:get()
  eq(d.status, "offline", "offline")
  eq(d.offline, true, "and says so")
  eq(d.params[gain.key], gain.min, "it keeps its parameter values")
  if pid then
    eq(
      os.execute("kill -0 " .. pid .. " 2>/dev/null") ~= 0 and os.execute("kill -0 " .. pid .. " 2>/dev/null") ~= true,
      true,
      "its helper is gone"
    )
  end
  fails(function() api.device_call(fx.id, "sandbox.pid") end, nil, "no process to ask")
  eq(render({ tail = 0.2 }).peak > quiet * 5, true, "the sound passes it by, in a render too")
  paw.project.save(path)
  local file = api.json_decode(T.read_file(path))
  eq(file.project.tracks[1].devices[2].offline, true, "the flag is saved")
  eq(file.project.tracks[1].devices[2].state, state, "with the state unchanged")
  fresh()
  paw.project.load(path)
  fx = paw.tracks()[1]:devices()[2]
  eq(fx:get().status, "offline", "and is offline when opened")
  fx:set_offline(false)
  eq(fx:get().status, "running", "set online, it runs")
  eq(fx.params[gain.key], gain.min, "with its parameter")
  eq(render({ tail = 0.2 }).peak <= quiet + 1e-6, true, "and its state")
  paw.undo()
  eq(fx:get().status, "offline", "undo sets it offline again")
end)

test("a project opens with every plugin offline, and they come up together or one by one", function()
  local kind = sandboxed_limiter()
  if not kind then return "skipped: test plugins not found" end
  local path, gain = saved_limiter(kind, "all-offline")
  paw.tracks()[1]:add_device(kind)
  paw.project.save(path)
  fresh()
  paw.open(path, { plugins_offline = true })
  local devices = paw.tracks()[1]:devices()
  eq(devices[1]:get().status, "running", "a built-in device is not a plugin")
  eq(devices[2]:get().status .. " " .. devices[3]:get().status, "offline offline", "every plugin is offline")
  eq(paw.project.modified, false, "the project is as it was opened")
  -- One at a time, as the device panel's `o` does.
  paw.frontend.act.toggle_offline(devices[3].id)
  eq(devices[3]:get().status, "running", "one comes up")
  paw.commands.exec("plugins.online")
  eq(devices[2]:get().status, "running", "and the rest with :plugins.online")
  eq(devices[2].params[gain.key], gain.min, "with its parameter")
  fresh()
  paw.commands.exec("edit " .. path .. " offline")
  eq(paw.tracks()[1]:devices()[2]:get().status, "offline", ":edit <path> offline does the same")
end)

test("a safety copy can be recovered with its plugins offline", function()
  local kind = sandboxed_limiter()
  if not kind then return "skipped: test plugins not found" end
  local path = saved_limiter(kind, "recover-offline")
  local copy = T.scratch .. "/recover-offline-copy.json"
  api.project_backup(copy, { path = path })
  fresh()
  paw.autosave.recover(copy, { plugins_offline = true })
  eq(paw.tracks()[1]:devices()[2]:get().status, "offline", "recovered with the plugin offline")
end)

test("a plugin that could not be loaded is opened offline next time, until it loads", function()
  local kind = sandboxed_limiter()
  if not kind then return "skipped: test plugins not found" end
  local path, gain = saved_limiter(kind, "remembered")
  return apart(function()
    fresh()
    paw.open(path)
    local fx = paw.tracks()[1]:devices()[2]
    hang_while_made(fx)
    T.until_(function() return fx:get().status == "stopped" end, "the plugin that hangs to fail to load")
    eq(#paw.loading.suggested(path), 1, "and is remembered")
    eq(io.open(paw.loading.project_dir(path) .. "/plugins.json") ~= nil, true, "in the project's state directory")
    eq(T.read_file(path):find('"offline"') == nil, true, "not in the project file")
    fresh()
    paw.open(path)
    fx = paw.tracks()[1]:devices()[2]
    eq(fx:get().status, "offline", "the next open has it offline")
    paw.commands.exec("plugins.online")
    T.until_(function() return fx:get().status == "running" end, "the plugin brought up to load")
    eq(fx.params[gain.key], gain.min, "with its parameter")
    eq(#paw.loading.suggested(path), 0, "and is no longer remembered")
    fresh()
    paw.open(path)
    eq(paw.tracks()[1]:devices()[2]:get().status ~= "offline", true, "so the next open loads it")
  end)
end)

-- The audio device going away ---------------------------------------------------

--- Run `fn` on the `test` backend, whose device can be unplugged, and put
--- the backend that ran before back afterwards.
local function on_test_device(fn)
  local backend = api.engine_get().backend
  api.audio_test_device({ present = true, fail_after = 0, back_after = 0 })
  api.audio_watch({ period = 100 })
  api.engine_restart({
    backend = "test",
    sample_rate = 44100,
    buffer_size = 256,
    test_input = { frequency = 440, level = -12, channels = 2 },
  })
  local events = { lost = {}, restored = {} }
  local handlers = {
    paw.on("audio.lost", function(e) events.lost[#events.lost + 1] = e end),
    paw.on("audio.restored", function(e) events.restored[#events.restored + 1] = e end),
  }
  local ok, err = xpcall(fn, debug.traceback, events)
  for _, h in ipairs(handlers) do
    paw.off(h)
  end
  paw.opt.audio_reconnect = true
  api.audio_watch({ period = 3000 })
  api.audio_test_device({ present = true, fail_after = 0, back_after = 0 })
  api.engine_restart({ backend = backend })
  if not ok then error(err, 0) end
  return err
end

test("a lost audio device stops the transport, keeps the take, and is opened again when it is back", function()
  return on_test_device(function(events)
    fresh()
    local t = paw.add_track({ name = "Gtr" })
    t.input = "1/2"
    t.armed = true
    paw.transport.record()
    T.advance_until(function() return paw.transport.position > 0.5 end, "half a beat of the take", 5000)
    eq(paw.transport.playing, true, "recording")
    api.audio_test_device({ fail_after = 1 }) -- unplugged at the next block
    T.advance_until(function() return #events.lost > 0 end, "the loss to be told", 5000)
    eq(events.lost[1].device:find("test device") ~= nil, true, "naming the device: " .. events.lost[1].device)
    eq(events.lost[1].recording, true, "and that a take was being made")
    eq(paw.transport.playing, false, "the transport has stopped")
    T.until_recorded()
    eq(#t:clips(), 1, "the take is kept")
    eq(t:clips()[1].length > 0, true, "with what was recorded")
    local e = api.engine_get()
    eq(e.backend, "null", "the program goes on without sound")
    eq(e.lost and e.lost.device, events.lost[1].device, "and says what it waits for")
    eq(paw.audio.summary():find("lost") ~= nil, true, "the engine summary says so: " .. paw.audio.summary())
    -- Work goes on.
    t.volume = -3
    paw.project.save(T.scratch .. "/lost.json")
    eq(render({ tail = 0 }).frames > 0, true, "rendering works")
    -- Past the looks for it (each 100 ms), while it is gone.
    T.advance(400)
    eq(#events.restored, 0, "not reopened while it is gone")
    eq(paw.reconnect.reconnect(), false, ":audio.reconnect says it is not back")
    api.audio_test_device({ present = true })
    T.advance_until(function() return #events.restored > 0 end, "the device to be found again when it is back", 5000)
    e = api.engine_get()
    eq(e.backend .. " " .. e.device, "test test device", "the device is open again")
    eq(
      e.sample_rate .. " " .. e.buffer_size .. " " .. e.input_channels,
      "44100 256 2",
      "with the same rate, block and input"
    )
    eq(e.lost, nil, "nothing is waited for")
    eq(t.input, "1/2", "the track keeps its input")
    paw.transport.play()
    T.advance_until(function() return paw.transport.position > 0 end, "the song to play on the device", 5000)
    T.stop()
  end)
end)

test("with automatic reopening off, a device that is back is opened by :audio.reconnect", function()
  return on_test_device(function(events)
    fresh()
    paw.opt.audio_reconnect = false
    api.audio_test_device({ fail_after = 1 })
    T.advance_until(function() return #events.lost > 0 end, "the loss to be told", 5000)
    eq(events.lost[1].auto, false, "and not to be reopened by itself")
    api.audio_test_device({ present = true })
    -- Past the looks for it (each 100 ms), while it is back.
    T.advance(500)
    eq(#events.restored, 0, "back, but not reopened")
    paw.commands.exec("audio.reconnect")
    T.until_(function() return #events.restored > 0 end, ":audio.reconnect to reopen it")
    eq(api.engine_get().backend, "test", "the device is open")
  end)
end)

test("a MIDI input that goes away and comes back is told of, and its tracks take it again", function()
  fresh()
  local t = paw.add_track({ name = "Keys" })
  t:add_device("synth", { attack = 0.001, release = 0.01 })
  t.midi_input = { port = "Keys A" }
  t.armed = true
  -- Only the test's own ports: the machine's real ones may come and go
  -- meanwhile, as other programs open and close theirs.
  local seen, ours = {}, { ["Keys A"] = true, Pads = true }
  local function note(word)
    return function(e)
      if ours[e.port] then seen[#seen + 1] = word .. " " .. e.port .. " " .. table.concat(e.tracks, ",") end
    end
  end
  -- Both ports there first, whatever an earlier test left.
  -- The ports are looked at each 200 ms of the clock: past a look, both
  -- are there, whatever an earlier test left.
  api.midi_test_ports({ "Keys A", "Pads" })
  T.advance(300)
  local handlers = { paw.on("midi.lost", note("lost")), paw.on("midi.returned", note("back")) }
  api.midi_test_ports({ "Pads" })
  T.advance_until(function() return #seen >= 1 end, "the port's going to be told", 1000)
  api.midi_test_ports({ "Pads", "Keys A" })
  T.advance_until(function() return #seen >= 2 end, "the port's coming back to be told", 1000)
  -- Past more looks: told once each, no more come.
  T.advance(500)
  for _, h in ipairs(handlers) do
    paw.off(h)
  end
  eq(table.concat(seen, "; "), "lost Keys A Keys; back Keys A Keys", "the port's going and coming back, with its track")
  eq(t.midi_input.port, "Keys A", "the track still chooses it")
  api.midi_test_ports({})
  T.advance(300)
end)

-- Choosing the device ------------------------------------------------------------

test(":audio offers the sample rate and the sound system beside the devices and block sizes", function()
  local groups = {}
  for _, choice in ipairs(paw.audio.engine_choices()) do
    groups[choice.group] = (groups[choice.group] or 0) + 1
  end
  eq(
    groups.rate ~= nil and groups.backend ~= nil and groups.block ~= nil,
    true,
    "rate, sound system and block size are offered"
  )
  local menu = paw.frontend.engine_menu()
  eq(#menu.rate, groups.rate, "the window's menu has the rates")
  eq(#menu.backend, groups.backend, "and the sound systems")
  fails(
    function() paw.audio.use({ backend = "no-such-system" }) end,
    "auto",
    "an unknown sound system, refused with the list"
  )
  paw.audio.use({ rate = 44100 })
  eq(api.engine_get().sample_rate, 44100, "a rate is chosen")
  local checked
  for _, choice in ipairs(paw.audio.engine_choices()) do
    if choice.group == "rate" and choice.checked then checked = choice.value.rate end
  end
  eq(checked, 44100, "and shown as chosen")
  paw.audio.use({ rate = 48000 })
end)
