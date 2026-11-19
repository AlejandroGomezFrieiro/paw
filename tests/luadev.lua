-- Tests of devices written in Lua (paw.luadev, paw.dsp, the paw-luadev
-- crate). Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, near, fails, fresh, render = T.test, T.eq, T.near, T.fails, T.fresh, T.render
local tone, channel_peaks = T.tone, T.channel_peaks
local api = paw.api

local dirs = 0

--- A directory of its own holding `scripts` (file name to source), looked
--- in for devices from now on.
local function scripts(files)
  dirs = dirs + 1
  local dir = T.scratch .. "/luadev" .. dirs
  os.execute("mkdir -p '" .. dir .. "'")
  for name, text in pairs(files) do T.write_file(dir .. "/" .. name, text) end
  return dir, paw.luadev.add_dir(dir)
end

-- Multiplies by a gain in dB.
local GAIN = [[
local dsp = require("paw.dsp")
local dev = dsp.device {
  name = "Test gain",
  params = { { key = "gain", name = "Gain", min = -60, max = 12, default = 0, unit = "dB" } },
}
function dev.process(b)
  local g = dsp.gain(b.params.gain) * SCALE
  for i = 0, b.frames - 1 do
    b.left[i] = b.left[i] * g
    b.right[i] = b.right[i] * g
  end
end
return dev
]]

local function gain_script(scale) return GAIN:gsub("SCALE", tostring(scale or 1)) end


test("a device written in Lua is listed among the devices, as lua:<file>", function()
  fresh()
  local _, found = scripts({ ["listed_gain.lua"] = gain_script() })
  eq(#found.errors, 0, "it loaded")
  eq(found.added[1], "lua:listed_gain", "found")
  local info
  for _, t in ipairs(paw.device_types()) do
    if t.kind == "lua:listed_gain" then info = t end
  end
  eq(info and info.name, "Test gain", "with the name it gives")
  eq(info.format .. " " .. info.category, "lua effect", "as an effect written in Lua")
  eq(info.params[1].key .. " " .. info.params[1].unit, "gain dB", "with its parameters")
end)

test("a Lua device changes the sound by the numbers it says", function()
  fresh()
  scripts({ ["numbers_gain.lua"] = gain_script(), ["numbers_dc.lua"] = [[
    local dev = require("paw.dsp").device {
      params = { { key = "level", min = -1, max = 1, default = 0.25 } },
    }
    function dev.sample(l, r, b) return b.params.level, -b.params.level / 2 end
    return dev
  ]] })
  local t = tone("tone", 4)
  local dry = render({ tail = 0, bits = 32 }).peak
  local fx = t:add_device("lua:numbers_gain", { gain = -6.0206 })
  eq(fx:get().stopped, nil, "it runs")
  near(render({ tail = 0, bits = 32 }).peak / dry, 0.5, 1e-4, "-6 dB halves the level")
  fx:set("gain", 0)
  near(render({ tail = 0, bits = 32 }).peak / dry, 1, 1e-6, "0 dB leaves it as it was")
  fx:remove()
  local dc = t:add_device("lua:numbers_dc")
  local info = render({ tail = 0, bits = 16 })
  local left, right = channel_peaks(info, 0.5, 1.5)
  near(left, 0.25, 1e-3, "one sample at a time, left")
  near(right, 0.125, 1e-3, "and right")
  dc:set("level", 0.5)
  near((channel_peaks(render({ tail = 0, bits = 16 }), 0.5, 1.5)), 0.5, 1e-3, "following its parameter")
end)

test("the luafx devices: gain and pan, drive, chords and sine", function()
  fresh()
  local ext = paw.ext.load("extensions/luafx")
  eq(ext.ok, true, "the extension loads")
  local t = tone("tone", 4)
  local dry = render({ tail = 0, bits = 16 })
  local dry_left = channel_peaks(dry, 0.5, 1.5)
  local gp = t:add_device("lua:gain_pan", { gain = -6.0206, pan = -1 })
  local left, right = channel_peaks(render({ tail = 0, bits = 16 }), 0.5, 1.5)
  near(left / dry_left, 0.5, 0.01, "gain and pan: the left side at half")
  eq(right < 1e-4, true, "and the right silent")
  gp:remove()
  t:add_device("lua:drive", { drive = 36, output = 0, tone = 16000 })
  local driven = render({ tail = 0, bits = 32 }).peak
  eq(driven > dry.peak * 1.5 and driven < 1.5, true, "drive: louder, and clipped softly (" .. driven .. ")")

  -- A chord of three from one note, heard by a device that counts them.
  scripts({ ["count_notes.lua"] = [[
    local dsp = require("paw.dsp")
    local dev = dsp.device { category = "instrument" }
    local held = 0
    function dev.process(b)
      for i = 0, b.nevents - 1 do
        local e = b.events[i]
        if e.type == dsp.NOTE_ON then held = held + 1 elseif e.type == dsp.NOTE_OFF then held = held - 1 end
      end
      for i = 0, b.frames - 1 do b.left[i], b.right[i] = held / 10, held / 10 end
    end
    return dev
  ]] })
  local c = paw.add_track({ name = "chords" })
  c:add_device("lua:chords", { chord = 1 })
  c:add_device("lua:count_notes")
  c:add_clip({ start = 0, length = 4, notes = { { pitch = "C4", start = 0, length = 2 } } })
  t.mute = true
  local info = render({ tail = 0, bits = 16 })
  near((channel_peaks(info, 0.2, 0.8)), 0.3, 1e-3, "chords: three notes held for one")
  eq((channel_peaks(info, 1.2, 1.8)) < 1e-3, true, "and all three let go")

  local s = paw.add_track({ name = "sine" })
  s:add_device("lua:sine")
  s:add_clip({ start = 0, length = 4, notes = { { pitch = "A4", start = 0, length = 2, velocity = 127 } } })
  c.mute = true
  info = render({ tail = 0, bits = 16 })
  near((channel_peaks(info, 0.2, 0.8)), 0.25, 0.01, "sine: a note at -12 dB")
  near(T.frequency(info, 0.2, 0.8), 440, 2, "at its pitch")
end)

test("a Lua device's parameters automate, are learnt and are saved", function()
  fresh()
  scripts({ ["auto_gain.lua"] = gain_script() })
  local t = tone("tone", 8)
  local fx = t:add_device("lua:auto_gain")
  fx:automate("gain"):set_points({ { 4, 0 }, { 4, -60 } })
  local info = render({ tail = 0, bits = 16 })
  eq((channel_peaks(info, 0.5, 1.5)) > 0.05, true, "sounds before the step")
  eq((channel_peaks(info, 2.5, 3.5)) < 0.005, true, "nearly silent after it")
  eq(fx.params.gain, 0, "the project keeps its own value")

  api.device_set_param(fx.id, "gain", -20)
  paw.flush()
  eq(paw.learn.last.param, "gain", "the parameter moved last is known")
  paw.cmd("learn")
  paw.midi.inject({ type = "cc", number = 21, value = 0, channel = 1 })
  paw.flush()
  eq(paw.learn.learning, nil, "bound by the controller's first move")
  paw.midi.inject({ type = "cc", number = 21, value = 1, channel = 1 })
  paw.flush()
  near(api.device_get(fx.id).params.gain, 12, 1e-6, "the controller moves it")
  paw.learn.clear()

  local path = T.scratch .. "/luadev-saved.json"
  fx:set("gain", -9)
  paw.project.save(path)
  paw.project.load(path)
  local again = paw.tracks()[1]:devices()[2]
  eq(again.kind, "lua:auto_gain", "the device comes back")
  eq(again.params.gain, -9, "with its value")
end)

test("a script that fails is shown as stopped with its error, and starts again", function()
  fresh()
  scripts({ ["fails_on_cue.lua"] = [[
    local dev = require("paw.dsp").device { params = { { key = "fail", min = 0, max = 1, default = 0 } } }
    function dev.process(b)
      if b.params.fail > 0.5 then error("asked to fail") end
    end
    return dev
  ]] })
  local t = tone("tone", 8)
  local fx = t:add_device("lua:fails_on_cue")
  local pid = tonumber(api.device_call(fx.id, "sandbox.pid"))
  eq(pid ~= api.env().pid, true, "it runs in a process of its own")
  local stopped = {}
  local handler = paw.on("device.stopped", function(e) stopped[#stopped + 1] = e end)
  paw.transport.play()
  fx:set("fail", 1)
  T.until_(function() return #stopped > 0 end, "the device to stop", 5000)
  paw.transport.stop()
  paw.off(handler)
  eq(stopped[1].device, fx.id, "the stop is told")
  eq(stopped[1].reason:match("fails_on_cue%.lua:%d+: asked to fail") ~= nil, true,
    "with the script's own error and line (" .. stopped[1].reason .. ")")
  eq(fx:get().stopped ~= nil, true, "the device says it has stopped")
  eq(#t:devices(), 2, "and is still in the project")
  local dry = render({ tail = 0 }).peak
  eq(dry > 0.05, true, "the track plays on, the effect passed over")

  fx:set("fail", 0)
  fx:restart()
  eq(fx:get().stopped, nil, "started again, it is well")
  eq(tonumber(api.device_call(fx.id, "sandbox.pid")) ~= pid, true, "in a new process")

  -- A crash of the process itself, as a script misusing ffi would cause.
  pid = tonumber(api.device_call(fx.id, "sandbox.pid"))
  stopped = {}
  handler = paw.on("device.stopped", function(e) stopped[#stopped + 1] = e end)
  paw.transport.play()
  T.next_block(10)
  os.execute("kill -KILL " .. pid)
  T.until_(function() return #stopped > 0 end, "the crash to be told", 5000)
  paw.transport.stop()
  paw.off(handler)
  eq(stopped[1].reason, "it was killed", "a killed helper is told")
  fx:restart()
  eq(fx:get().stopped, nil, "and starts again")
end)

test("a script that does not load says why, and nothing else is hurt", function()
  fresh()
  local _, found = scripts({
    ["broken_syntax.lua"] = "local dev = require('paw.dsp').device { }\nfunction dev.process(b) b.left[0] = = 1 end\nreturn dev\n",
    ["no_process.lua"] = "return require('paw.dsp').device { name = 'Nothing' }\n",
    ["never_ready.lua"] = "while true do end\n",
    ["good_one.lua"] = gain_script(),
  })
  local why = {}
  for _, e in ipairs(found.errors) do why[e.kind] = e.error end
  eq(why["lua:broken_syntax"]:match("broken_syntax%.lua:2:") ~= nil, true, "a syntax error, with its line (" .. why["lua:broken_syntax"] .. ")")
  eq(why["lua:no_process"]:find("neither `process` nor `sample`", 1, true) ~= nil, true, "a device that runs nothing")
  eq(why["lua:never_ready"]:find("did not get ready within", 1, true) ~= nil, true, "a loop that never ends")
  eq(found.added[1], "lua:good_one", "the others load")
  fails(function() paw.add_track({ name = "x" }):add_device("lua:broken_syntax") end, nil, "a script that did not load cannot be added")
  local listed = {}
  for _, s in ipairs(api.lua_devices()) do listed[s.kind] = s end
  eq(listed["lua:broken_syntax"].error ~= nil, true, "the listing says why")
end)

test("a script changed on the disk is loaded again, and its devices keep their values", function()
  fresh()
  local dir = scripts({ ["reload_gain.lua"] = gain_script(1) })
  local t = tone("tone", 4)
  local dry = render({ tail = 0, bits = 32 }).peak
  local fx = t:add_device("lua:reload_gain")
  fx:set("gain", -6.0206)
  near(render({ tail = 0, bits = 32 }).peak / dry, 0.5, 1e-4, "before")
  local pid = api.device_call(fx.id, "sandbox.pid")

  -- The new version halves again, and has a second parameter.
  local text = gain_script(0.5):gsub('unit = "dB" }', 'unit = "dB" }, { key = "extra", default = 0.3 }')
  T.write_file(dir .. "/reload_gain.lua", text)
  local found = paw.luadev.check()
  eq(found.changed[1], "lua:reload_gain", "the change is seen")
  eq(api.device_call(fx.id, "sandbox.pid") ~= pid, true, "the device started again")
  near(fx.params.gain, -6.0206, 1e-5, "keeping its value")
  near(fx:get().params.extra, 0.3, 1e-6, "with the new parameter at its default")
  near(render({ tail = 0, bits = 32 }).peak / dry, 0.25, 1e-4, "and the new code running")

  -- A version that does not load leaves the running one alone.
  pid = api.device_call(fx.id, "sandbox.pid")
  T.write_file(dir .. "/reload_gain.lua", "this is not Lua")
  found = paw.luadev.check()
  eq(#found.errors, 1, "the error is told")
  eq(api.device_call(fx.id, "sandbox.pid"), pid, "the device goes on as it was")

  -- By command, with the file as it is.
  T.write_file(dir .. "/reload_gain.lua", gain_script(1))
  paw.ui.focus("arrange")
  paw.cursor.set_track(t)
  paw.cmd("device.reload")
  eq(api.device_call(fx.id, "sandbox.pid") ~= pid, true, ":device.reload starts it again")
  near(render({ tail = 0, bits = 32 }).peak / dry, 0.5, 1e-4, "from the file as it is now")
end)

test("a script in the configuration's devices wins over an extension's of the same name", function()
  fresh()
  local low = scripts({ ["ranked.lua"] = gain_script():gsub('"Test gain"', '"Low"') })
  dirs = dirs + 1
  local high = T.scratch .. "/luadev" .. dirs
  os.execute("mkdir -p '" .. high .. "'")
  T.write_file(high .. "/ranked.lua", (gain_script():gsub('"Test gain"', '"High"')))
  paw.luadev.add_dir(high, paw.luadev.RANK_CONFIG)
  local name
  for _, t in ipairs(paw.device_types()) do
    if t.kind == "lua:ranked" then name = t.name end
  end
  eq(name, "High", "the higher rank's")
  T.write_file(low .. "/ranked.lua", (gain_script():gsub('"Test gain"', '"Low again"')))
  paw.luadev.check()
  for _, t in ipairs(paw.device_types()) do
    if t.kind == "lua:ranked" then name = t.name end
  end
  eq(name, "High", "even after the lower one changes")
end)

test("scripts call a Lua device, and what is posted to its kind reaches every one, a render's too", function()
  fresh()
  scripts({ ["posted_level.lua"] = [[
    local dsp = require("paw.dsp")
    local dev = dsp.device { category = "instrument" }
    local level = 0
    function dev.call(method, data)
      if method == "level" then level = tonumber(data) end
      if method == "get" then return level end
      if method == "map" then local m = dsp.map(data) level = m.data[1] m:close() end
    end
    function dev.process(b)
      for i = 0, b.frames - 1 do b.left[i], b.right[i] = level, level end
    end
    return dev
  ]] })
  local a = paw.add_track({ name = "a" })
  local first = a:add_device("lua:posted_level")
  a:add_clip({ start = 0, length = 4 })
  eq(api.device_call(first.id, "get"), "0", "a call answers")
  eq(#api.device_post("lua:posted_level", "level", "0.25"), 0, "taken by every device")
  eq(api.device_call(first.id, "get"), "0.25", "the device there is told at once")
  near(render({ tail = 0, bits = 32, ["end"] = 2 }).peak, 0.25, 1e-6, "and so is the render's own")
  local later = paw.add_track({ name = "b" }):add_device("lua:posted_level")
  eq(api.device_call(later.id, "get"), "0.25", "a device made later is given what was posted")
  -- Large data goes as a file, which the device maps.
  local ffi = require("ffi")
  local path = T.scratch .. "/posted.f32"
  T.write_file(path, ffi.string(ffi.new("float[2]", 0.5, 0.125), 8))
  api.device_post("lua:posted_level", "map", path)
  eq(api.device_call(later.id, "get"), "0.125", "a file of floats is read by mapping it")
  api.device_post("lua:posted_level", "map", nil)
  local c = paw.add_track({ name = "c" }):add_device("lua:posted_level")
  eq(api.device_call(c.id, "get"), "0.25", "a topic posted nil is forgotten")
  api.device_post("lua:posted_level", "level", nil)
end)
