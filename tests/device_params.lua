-- Every device's parameters through one description: paw's place, the
-- device's own id, the kind of value, flags, text both ways, and lanes
-- and values that keep to the device's own id when a plugin changes.
local T = ...
local test, eq, near, fails, fresh = T.test, T.eq, T.near, T.fails, T.fresh
local paw = require("paw")
local api = paw.api

local function by_key(d, key)
  for _, p in ipairs(d.param_info) do
    if p.key == key then return p end
  end
end

test("device params: one description for each parameter of a built-in device", function()
  fresh()
  local part = paw.add_part({ name = "lead" })
  local synth = part:add_device("synth")
  local d = synth:get()
  eq(d.plugin, nil, "a built-in device is not a plugin")
  local wave, cutoff = by_key(d, "wave"), by_key(d, "cutoff")
  eq(wave.index, 1, "paw's place in the list, from 1")
  eq(wave.id, "wave", "a built-in parameter's own id is its key")
  eq(wave.kind, "enum", "named options")
  eq(wave.steps, 3, "four options are three steps")
  eq(cutoff.kind, "continuous", "a continuous parameter")
  eq(cutoff.automatable, true, "it can be automated")
  eq(cutoff.read_only, false, "it takes values")
  eq(cutoff.automated, false, "nothing moves it yet")
  api.lane_add(part.id, { target = "param", device = synth.id, param = "cutoff", points = { { 0, 200 }, { 4, 8000 } } })
  eq(by_key(synth:get(), "cutoff").automated, true, "a lane moves it")
end)

test("device params: values as text and back, the same as the device panel shows", function()
  fresh()
  local part = paw.add_part({ name = "lead" })
  local synth = part:add_device("synth")
  local eqd = part:add_device("eq")
  for _, case in ipairs({
    { synth, "cutoff", 2500 },
    { synth, "gain", -18 },
    { synth, "wave", 2 },
    { synth, "attack", 0.25 },
    { eqd, "b5_freq", 12500 },
    { eqd, "b5_q", 0.71 },
  }) do
    local dev, key, value = case[1], case[2], case[3]
    eq(api.device_param_text(dev.id, key, value), paw.params.format(by_key(dev:get(), key), value), key .. " as text")
  end
  eq(api.device_param_text(synth.id, "cutoff", 2500), "2.5 kHz", "in the unit's own size")
  eq(api.device_param_parse(synth.id, "cutoff", "2.5 kHz"), 2500, "and back")
  eq(api.device_param_parse(synth.id, "wave", "Square"), 2, "an option by name")
  fails(function() api.device_param_parse(synth.id, "cutoff", "bright") end, "not a value", "text that is no value")
  local p = api.device_param(synth.id, "cutoff")
  eq(p.value, p.default, "one parameter, with its value")
  eq(p.text, "4 kHz", "and its text")
end)

test("device params: set by text and by the device's own id, and told with that id", function()
  fresh()
  local part = paw.add_part({ name = "lead" })
  local synth = part:add_device("synth")
  api.device_set_param(synth.id, "cutoff", "1.2 kHz")
  eq(synth:get().params.cutoff, 1200, "a value given as text")
  api.device_set_param(synth.id, "Wave", "triangle")
  eq(synth:get().params.wave, 3, "an option by name, the parameter by its shown name")
  fails(function() api.device_set_param(synth.id, "cutoff", "loud") end, "not a value", "text that is no value")
  local seen
  local id = paw.on("param.touched", function(e) seen = e end)
  api.device_set_param(synth.id, "release", 0.5)
  paw.flush()
  paw.off(id)
  eq(seen and seen.id, "release", "the event carries the device's own id")
  eq(require("paw.fx").last_touched.id, "release", "and so does the parameter last moved")
end)

-- With the dev shell's plugins (tests/tools/suite.sh plugins) -------------------------

local function plugin_kind(format, name)
  for _, info in ipairs(api.device_types()) do
    if info.format == format and (info.name == name or info.name == "LSP " .. name) then return info.kind, info end
  end
end

for _, format in ipairs({ "clap", "lv2", "vst3" }) do
  test("device params: a " .. format .. " plugin's own ids, flags and text", function()
    local kind, info = plugin_kind(format, "Limiter Stereo")
    if not kind then return "skipped: test plugins not found" end
    fresh()
    local part = paw.add_part({ name = "lim" })
    local fx = part:add_device(kind)
    local d = fx:get()
    eq(d.plugin.format, format, "the plugin says its format")
    eq(d.plugin.id ~= "", true, "and its own id")
    eq(info.id, d.plugin.id, "the same as the kind's")
    if format == "vst3" then eq(d.plugin.id:match("^%x+$") and #d.plugin.id, 32, "a VST3 class id is 32 hex digits") end
    if format == "lv2" then eq(d.plugin.id:match("^http"), "http", "an LV2 plugin is a URI") end
    eq(d.plugin.vendor ~= "", true, "its vendor")
    local gain
    for _, p in ipairs(d.param_info) do
      if p.key == "input_gain" or p.key == "g_in" then gain = p end
    end
    eq(gain ~= nil, true, "found the input gain")
    if format == "lv2" then
      eq(gain.id, "g_in", "an LV2 parameter is its port's symbol")
    else
      eq(gain.id:match("^%d+$") ~= nil, true, "a plugin's own parameter id: " .. gain.id)
      eq(gain.id ~= gain.key, true, "which is not paw's key")
    end
    local mode = by_key(d, format == "lv2" and "mode" or "operating_mode")
    eq(mode.kind ~= "continuous", true, "the operating mode takes steps: " .. mode.kind)
    -- The plugin's own text for a value, and its own reading of a text.
    local text = api.device_param_text(fx.id, gain.id, gain.max)
    eq(text ~= "", true, "a value as the plugin writes it: " .. text)
    near(api.device_param_parse(fx.id, gain.id, text), gain.max, 1e-3 * math.max(1, math.abs(gain.max)), "read back")
    api.device_set_param(fx.id, gain.id, gain.min)
    eq(fx:get().params[gain.key], gain.min, "set by the plugin's own id")
  end)

  test("device params: a " .. format .. " plugin's lanes and values keep to its own ids", function()
    local kind = plugin_kind(format, "Limiter Stereo")
    if not kind then return "skipped: test plugins not found" end
    if format == "lv2" then return "skipped: an LV2 parameter's key is its own id" end
    fresh()
    local part = paw.add_part({ name = "lim" })
    local fx = part:add_device(kind)
    local gain = by_key(fx:get(), "input_gain")
    -- A quarter of the way up: VST3 values go from 0 to 1, CLAP's in dB.
    local value = gain.min + (gain.max - gain.min) / 4
    api.device_set_param(fx.id, "input_gain", value)
    api.lane_add(
      part.id,
      { target = "param", device = fx.id, param = "input_gain", points = { { 0, gain.min }, { 4, gain.max } } }
    )
    local path = T.scratch .. "/ids-" .. format .. ".json"
    paw.project.save(path)
    local text = T.read_file(path)
    eq(
      text:find('"input_gain": "' .. gain.id .. '"', 1, true) ~= nil,
      true,
      "the project keeps the plugin's id of each key it uses"
    )
    -- A new version of the plugin calls the parameter otherwise: here the
    -- project knows it by another key, which only the id ties to it.
    T.write_file(path, (text:gsub('"input_gain"', '"in_level"')))
    fresh()
    paw.project.load(path)
    local loaded = paw.parts()[1]:devices()[1]
    local p = api.device_param(loaded.id, gain.id)
    eq(p.key, "in_level", "the parameter takes the key the project knows it by")
    eq(p.name, gain.name, "it is the same parameter")
    near(p.value, value, 1e-4, "with its value")
    eq(p.automated, true, "and its lane")
    eq(by_key(loaded:get(), "input_gain"), nil, "no other parameter took the old key")
  end)

  test("device params: a " .. format .. " chain written to its own file keeps the plugin's ids", function()
    local kind = plugin_kind(format, "Limiter Stereo")
    if not kind then return "skipped: test plugins not found" end
    if format == "lv2" then return "skipped: an LV2 parameter's key is its own id" end
    fresh()
    local part = paw.add_part({ name = "lim" })
    local fx = part:add_device(kind)
    local gain = by_key(fx:get(), "input_gain")
    local value = gain.min + (gain.max - gain.min) / 4
    api.device_set_param(fx.id, "input_gain", value)
    local dir = T.scratch .. "/chain-" .. format
    api.fs_mkdir(dir)
    api.chain_write(part.id, dir .. "/devices.json")
    local text = T.read_file(dir .. "/devices.json")
    eq(
      text:find('"input_gain": "' .. gain.id .. '"', 1, true) ~= nil,
      true,
      "the chain file keeps the plugin's id of each key"
    )
    -- A new version of the plugin names the parameter otherwise.
    T.write_file(dir .. "/devices.json", (text:gsub('"input_gain"', '"in_level"')))
    fresh()
    local other = paw.add_part({ name = "again" })
    api.part_chain_file(other.id, dir .. "/devices.json", true)
    local loaded = other:devices()[1]
    local p = api.device_param(loaded.id, gain.id)
    eq(p.key, "in_level", "the parameter takes the key of the chain file")
    near(p.value, value, 1e-4, "with its value")
    -- The first edit makes the chain the project's own: it is saved with the ids.
    api.undo_checkpoint()
    api.device_set_param(loaded.id, gain.id, gain.min)
    api.undo_checkpoint()
    paw.flush()
    eq(other:get().chain_source, nil, "the chain is the project's own now")
    local project = T.scratch .. "/chain-project-" .. format
    paw.project.save(project)
    local found
    for _, entry in ipairs(api.read_dir(project .. "/parts")) do
      local file = project .. "/parts/" .. entry.name .. "/devices.json"
      local saved = entry.is_dir and io.open(file) and T.read_file(file)
      if saved and saved:find('"in_level": "' .. gain.id .. '"', 1, true) then found = true end
    end
    eq(found, true, "the copied chain is saved in the project with the ids")
  end)
end
