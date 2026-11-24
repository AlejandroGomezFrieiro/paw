-- Plugins tests.
local T = ...
local test, eq, near, fails, fresh, render, tone = T.test, T.eq, T.near, T.fails, T.fresh, T.render, T.tone
local until_, next_block, scratch, channel_peaks = T.until_, T.next_block, T.scratch, T.channel_peaks
local paw = require("paw")
local api = paw.api

-- These need the plugins the dev shell provides (see PAW_TEST_PLUGINS) and are
-- skipped without them.

local function plugin_kind(format, pattern)
  for _, info in ipairs(paw.device_types()) do
    if info.format == format and info.name:find(pattern) then return info.kind end
  end
end

for _, format in ipairs({ "clap", "lv2", "vst3" }) do
  test(format .. " effects process audio, take parameters and keep their state", function()
    local kind = plugin_kind(format, "Limiter Stereo$")
    if not kind then return "skipped: test plugins not found" end
    fresh()
    local t = tone("tone", 2)
    local dry = render({ tail = 0.2 }).peak
    local fx = t:add_device(kind)
    local d = fx:get()
    eq(d.format, format, "format")
    eq(#d.param_info > 10, true, "the plugin lists its parameters")
    -- These plugins have windows of their own; built-in devices do not.
    -- (Opening one needs a display, so that is not done here.)
    eq(fx.editor, "closed", "the plugin offers an editor")
    eq(t:devices()[1].editor, nil, "a built-in device has none")
    fails(function() t:devices()[1]:open_editor() end, "no editor", "opening an editor that is not there")
    eq(render({ tail = 0.2 }).peak > dry * 0.3, true, "audio passes through")

    -- Turn the output gain all the way down, by whatever name the format gives it.
    local gain
    for _, p in ipairs(d.param_info) do
      if p.key == "output_gain" or p.key == "g_out" then gain = p end
    end
    eq(gain ~= nil, true, "found the output gain parameter")
    fx:set(gain.key, gain.min)
    eq(fx.params[gain.key], gain.min, "the value reads back")
    eq(render({ tail = 0.2 }).peak < dry * 0.05, true, "the parameter takes effect")
    fx.bypass = true
    near(render({ tail = 0.2 }).peak, dry, 0.01, "bypass")
    fx.bypass = false

    local path = paw.project.save(scratch .. "/" .. format .. ".json")
    fresh()
    paw.project.load(path)
    local loaded = paw.parts()[1]:devices()[2]
    eq(loaded.kind, kind, "the plugin is back after loading")
    eq(loaded.params[gain.key], gain.min, "with its parameter")
    eq(render({ tail = 0.2 }).peak < dry * 0.05, true, "and it still takes effect")

    -- Playing in real time and removing a plugin while it runs must both be safe.
    paw.transport.play()
    next_block(10)
    loaded:remove()
    next_block(10)
    paw.transport.stop()
    eq(#paw.parts()[1]:devices(), 1, "removed while playing")
    fails(function() paw.parts()[1]:add_device(format .. ":no-such-plugin") end, "no%-such%-plugin", "unknown plugin")
  end)

  test(format .. " plugins run in a process of their own, and one that dies is lost alone", function()
    local kind = plugin_kind(format, "Limiter Stereo$")
    if not kind then return "skipped: test plugins not found" end
    fresh()
    local t = tone("tone", 2)
    local dry = render({ tail = 0.2 }).peak
    local fx = t:add_device(kind)
    local pid = tonumber((select(2, pcall(api.device_call, fx.id, "sandbox.pid"))))
    if not pid then return "skipped: plugins are hosted in-process here" end
    eq(pid ~= api.env().pid, true, "the plugin has a process of its own")
    local gain
    for _, p in ipairs(fx:get().param_info) do
      if p.key == "output_gain" or p.key == "g_out" then gain = p end
    end
    fx:set(gain.key, gain.min)
    paw.project.save(scratch .. "/" .. format .. "-crash.json") -- the project now has the plugin's state
    local stopped = {}
    local handler = paw.on("device.stopped", function(e) stopped[#stopped + 1] = e end)
    paw.transport.play()
    next_block(10)
    os.execute("kill -KILL " .. pid)
    until_(function() return #stopped > 0 end, "the crash to be told")
    -- More blocks and looks at the device: told once, no second report comes.
    next_block(10)
    T.settle()
    paw.transport.stop()
    paw.off(handler)
    eq(#stopped, 1, "its crash is told, once")
    eq(stopped[1].device .. " " .. stopped[1].reason, fx.id .. " it was killed", "with the device and what happened")
    eq(fx:get().stopped ~= nil, true, "the device says that it has stopped")
    eq(#t:devices(), 2, "and is still in the project")
    fails(function() fx:open_editor() end, "not running", "asking a stopped plugin for something")
    fx:restart()
    eq(fx:get().stopped, nil, "started again, it is well")
    eq(fx.params[gain.key], gain.min, "with what the project had of it")
    eq(render({ tail = 0.2 }).peak < dry * 0.05, true, "and it works as it did")
    local again = tonumber(api.device_call(fx.id, "sandbox.pid"))
    eq(again ~= pid, true, "in a new process")
  end)

  test(format .. " parameters follow automation", function()
    local kind = plugin_kind(format, "Limiter Stereo$")
    if not kind then return "skipped: test plugins not found" end
    fresh()
    local t = tone("tone", 8)
    local fx = t:add_device(kind)
    local gain
    for _, p in ipairs(fx:get().param_info) do
      if p.key == "output_gain" or p.key == "g_out" then gain = p end
    end
    local base = fx.params[gain.key]
    fx:automate(gain.key):set_points({ { 4, base }, { 4, gain.min } })
    local info = render({ tail = 0, bits = 16 })
    eq(channel_peaks(info, 0.5, 1.5) > 0.05, true, "sounds before the step")
    eq(channel_peaks(info, 2.5, 3.5) < 0.005, true, "silent after it")
    eq(fx.params[gain.key], base, "the project keeps its own value")
  end)

  test(format .. " instruments play notes", function()
    local kind = plugin_kind(format, "^Surge XT$")
    if not kind then return "skipped: test plugins not found" end
    fresh()
    local t = paw.add_part({ name = "surge" })
    local synth = t:add_device(kind)
    eq(synth.format, format, "format")
    local clip = t:add_clip({ start = 0, length = 2, notes = { { pitch = "A3", start = 0, length = 1 } } })
    eq(render({ tail = 0.3 }).peak > 0.05, true, "a note sounds")
    clip.muted = true
    eq(render({ tail = 0.3 }).peak < 0.001, true, "no notes, no sound")
    -- Its state survives being saved and loaded.
    clip.muted = false
    local path = paw.project.save(scratch .. "/" .. format .. "-inst.json")
    fresh()
    paw.project.load(path)
    eq(render({ tail = 0.3 }).peak > 0.05, true, "sounds after loading")
  end)
end

test("a folder that an extension adds is searched for plugins of each format until it is removed", function()
  local before = api.plugins_dirs()
  if not before then return "skipped: this build hosts no plugins" end
  local dir = scratch .. "/plugins-dirs-added"
  os.execute("mkdir -p '" .. dir .. "'")
  paw.plugins.add_dir(dir, "dirs-test")
  local during = api.plugins_dirs()
  paw.plugins.remove_dir(dir)
  for _, format in ipairs({ "clap", "lv2", "vst3" }) do
    eq(#during[format], #before[format] + 1, format .. ": one more folder")
    eq(during[format][#during[format]], dir, format .. ": the added folder comes last")
    eq(#api.plugins_dirs()[format], #before[format], format .. ": not searched once removed")
  end
end)
