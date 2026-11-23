-- Devices as one works with them all day: `paw.fx` (runtime/lua/paw/fx.lua).
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

local function plugin_kind(format, pattern)
  for _, info in ipairs(paw.device_types()) do
    if info.format == format and info.name:find(pattern) then return info.kind end
  end
end

--- Run `fn` with the editor calls recorded instead of made, and with a
--- person at the program or not. Returns the ids whose editor was opened.
local function watching_editors(interactive, fn)
  local opened, real_editor, real_interactive = {}, api.device_editor, paw.fx.interactive
  api.device_editor = function(id, open)
    if open then opened[#opened + 1] = id end
    return true
  end
  paw.fx.interactive = function() return interactive end
  local ok, err = pcall(fn)
  api.device_editor, paw.fx.interactive = real_editor, real_interactive
  if not ok then error(err, 0) end
  return opened
end

-- Adding by hand -------------------------------------------------------------------

test("a plugin added by hand opens its editor; by a script, or with nobody there, it does not", function()
  local kind = plugin_kind("lv2", "Limiter Stereo$") or plugin_kind("clap", "Limiter Stereo$")
  if not kind then return "skipped: test plugins not found" end
  fresh()
  local track = paw.add_track({ name = "fx" })
  paw.cursor.set_track(track.id)
  local opened = watching_editors(true, function() paw.commands.exec("device.add " .. kind) end)
  eq(#opened, 1, "`:device.add` by hand opens the editor once")
  eq(opened[1], track:devices()[1].id, "of the device it added")
  opened = watching_editors(true, function() paw.frontend.act.add_device(kind) end)
  eq(#opened, 1, "the window's Add a device box does too")
  opened = watching_editors(true, function() track:add_device(kind) end)
  eq(#opened, 0, "a script's add_device does not")
  opened = watching_editors(false, function() paw.commands.exec("device.add " .. kind) end)
  eq(#opened, 0, "nor a command with nobody at the program")
  paw.opt.editor_on_add = false
  opened = watching_editors(true, function() paw.commands.exec("device.add " .. kind) end)
  paw.opt.editor_on_add = true
  eq(#opened, 0, "nor with the option off")
end)

test("a built-in device added by hand opens nothing", function()
  fresh()
  local track = paw.add_track({ name = "fx" })
  paw.cursor.set_track(track.id)
  local opened = watching_editors(true, function() paw.commands.exec("device.add synth") end)
  eq(#opened, 0, "the synth has no window of its own")
  eq(#track:devices(), 1, "but it is added")
end)

test("a script run is not a person at the program", function()
  paw.frontend.polled = nil -- the frontend tests ask for the state as a window does
  eq(paw.fx.interactive(), false, "no terminal and no window polling")
end)

-- Presets --------------------------------------------------------------------------

--- Remove what a test saved, so the next starts with none.
local function forget_presets(kind)
  for _, p in ipairs(paw.fx.user_presets(kind)) do
    paw.fx.delete(kind, p.name)
  end
  paw.fx.set_default(kind, nil)
end

test("presets: a built-in device is saved as a preset and loaded again, in one undo step", function()
  forget_presets("synth")
  fresh()
  local track = paw.add_track({ name = "keys" })
  local synth = track:add_device("synth")
  synth:set({ cutoff = 700, wave = 2 })
  local path = paw.fx.save(synth, "Dark square")
  eq(path:find(api.env().data_dir, 1, true) == 1, true, "the preset is in the user's data directory")
  eq(paw.fx.current(synth), "Dark square", "the device now holds that preset")
  synth:set({ cutoff = 9000, wave = 0 })
  api.undo_checkpoint()
  paw.fx.load(synth, "Dark square")
  eq(synth.params.cutoff, 700, "the cutoff comes back")
  eq(synth.params.wave, 2, "and the wave")
  paw.undo()
  eq(synth.params.cutoff, 9000, "one undo takes the whole preset back")
  eq(synth.params.wave, 0, "every parameter of it")
  -- Another project, another synth: the preset loads there too.
  fresh()
  local other = paw.add_track({ name = "other" }):add_device("synth")
  paw.fx.load(other, "dark sq")
  eq(other.params.cutoff, 700, "a preset loads into the same kind of device elsewhere, by part of its name")
  forget_presets("synth")
end)

test("presets: the user's come first, then the factory's, and next and previous step through them", function()
  forget_presets("synth")
  fresh()
  local synth = paw.add_track({ name = "keys" }):add_device("synth")
  paw.fx.save(synth, "Zed")
  local list = paw.fx.presets(synth)
  eq(list[1].name, "Zed", "the user's preset is first")
  eq(list[1].user, true, "and marked as the user's")
  eq(list[2].name, paw.fx.factory.synth[1].name, "then the factory's, in order")
  eq(list[2].factory, true, "marked as the factory's")
  paw.fx.load(synth, "Pluck")
  eq(synth.params.sustain, 0, "a factory preset sets its parameters")
  eq(synth.params.gain, -12, "and leaves the ones it does not name where they were")
  local at
  for i, p in ipairs(list) do
    if p.name == "Pluck" then at = i end
  end
  paw.fx.step(synth, 1)
  eq(paw.fx.current(synth), list[at + 1].name, "next is the one after")
  paw.fx.step(synth, -1)
  paw.fx.step(synth, -1)
  eq(paw.fx.current(synth), list[at - 1].name, "previous the one before")
  forget_presets("synth")
end)

test("presets: new devices added by hand start from the default preset; a script's do not", function()
  forget_presets("delay")
  fresh()
  local track = paw.add_track({ name = "fx" })
  paw.cursor.set_track(track.id)
  local delay = track:add_device("delay")
  delay:set("time", 123)
  paw.fx.save(delay, "Mine")
  paw.fx.set_default("delay", "Mine")
  local added = paw.fx.add(track, "delay")
  eq(added.params.time, 123, "added by hand, it starts from the default preset")
  eq(paw.fx.current(added), "Mine", "and says so")
  eq(track:add_device("delay").params.time, 375, "a script's starts as the device makes it")
  paw.fx.set_default("delay", nil)
  eq(paw.fx.add(track, "delay").params.time, 375, "with no default marked, neither does one added by hand")
  forget_presets("delay")
end)

test("presets: the commands and keys act on the device in the panel", function()
  forget_presets("synth")
  fresh()
  local track = paw.add_track({ name = "keys" })
  paw.cursor.set_track(track.id)
  local synth = track:add_device("synth")
  paw.flush()
  paw.ui.focus("devices")
  paw.ui.views:get("devices").row = 1
  paw.commands.exec("preset Sub bass")
  eq(synth.params.cutoff, 400, ":preset <name> loads it")
  T.keys("]p")
  eq(paw.fx.current(synth), "Saw bass", "]p is the next preset")
  T.keys("[p")
  eq(paw.fx.current(synth), "Sub bass", "[p the previous")
  paw.commands.exec("preset.save Low")
  eq(paw.fx.user_presets("synth")[1].name, "Low", ":preset.save keeps one")
  paw.commands.exec("preset.default")
  eq(paw.fx.default_preset("synth"), "Low", ":preset.default marks the one loaded")
  T.keys("c")
  eq(paw.pick.state() ~= nil, true, "c on the device opens the preset picker")
  T.keys("<Esc>")
  forget_presets("synth")
end)

test("presets: the window's card shows the preset, steps through them and lists them in a menu", function()
  forget_presets("delay")
  fresh()
  local track = paw.add_track({ name = "fx" })
  paw.cursor.set_track(track.id)
  local delay = track:add_device("delay")
  local A = paw.frontend.act
  A.preset_step(delay.id, 1)
  eq(paw.frontend.state(-1).devices[1].preset, "Slapback", "the card names the first preset after ▶")
  local menu = A.preset_menu(delay.id)
  eq(menu[1], "● Slapback  · factory", "the menu marks the one loaded and the factory's")
  A.preset_choose(delay.id, 3)
  eq(paw.fx.current(delay), "Dotted eighth", "choosing from the menu loads it")
  A.device_command(delay.id, "preset.save Long")
  eq(paw.fx.user_presets("delay")[1].name, "Long", "the menu's Save as a preset… saves it")
  forget_presets("delay")
end)

-- Presets of plugins: their state is what the preset keeps.
for _, format in ipairs({ "clap", "lv2", "vst3" }) do
  test(format .. " presets: a plugin's state is saved, loaded, and undone", function()
    local kind = plugin_kind(format, "Limiter Stereo$")
    if not kind then return "skipped: test plugins not found" end
    forget_presets(kind)
    fresh()
    local fx = paw.add_track({ name = "fx" }):add_device(kind)
    local gain
    for _, p in ipairs(fx:get().param_info) do
      if p.key == "output_gain" or p.key == "g_out" then gain = p end
    end
    fx:set(gain.key, gain.min)
    paw.fx.save(fx, "Quiet")
    fx:set(gain.key, gain.max)
    api.undo_checkpoint()
    paw.fx.load(fx, "Quiet")
    T.near(fx.params[gain.key], gain.min, 1e-3, "the plugin is back where the preset was")
    paw.undo()
    T.near(fx.params[gain.key], gain.max, 1e-3, "undo puts the plugin back as it was before")
    paw.redo()
    T.near(fx.params[gain.key], gain.min, 1e-3, "and redo loads the preset again")
    forget_presets(kind)
  end)
end

test("clap presets: Surge XT's own presets are listed and loaded", function()
  local kind = plugin_kind("clap", "^Surge XT$")
  if not kind then return "skipped: test plugins not found" end
  fresh()
  local surge = paw.add_track({ name = "surge" }):add_device(kind)
  local factory = paw.fx.factory_presets(surge)
  eq(#factory > 10, true, "Surge XT lists its patches (" .. #factory .. ")")
  local before = api.device_state(surge.id)
  api.undo_checkpoint()
  paw.fx.load(surge, factory[5])
  eq(paw.fx.current(surge), factory[5].name, "the device takes the patch's name")
  eq(api.device_state(surge.id) ~= before, true, "and the plugin's state changed")
  paw.undo()
  eq(paw.fx.current(surge), nil, "undo forgets it")
end)

test("lv2 presets: the presets a bundle describes are listed and loaded", function()
  local kind = plugin_kind("lv2", "^Surge XT$")
  if not kind then return "skipped: test plugins not found" end
  fresh()
  local surge = paw.add_track({ name = "surge" }):add_device(kind)
  local factory = paw.fx.factory_presets(surge)
  eq(#factory >= 1, true, "Surge XT's LV2 bundle has a preset")
  paw.fx.load(surge, factory[1])
  eq(paw.fx.current(surge), factory[1].name, "it loads")
end)

test("vst3 presets: a .vstpreset file is loaded", function()
  local kind = plugin_kind("vst3", "Limiter Stereo$")
  if not kind then return "skipped: test plugins not found" end
  fresh()
  local fx = paw.add_track({ name = "fx" }):add_device(kind)
  local gain
  for _, p in ipairs(fx:get().param_info) do
    if p.key == "output_gain" or p.key == "g_out" then gain = p end
  end
  fx:set(gain.key, gain.min)
  paw.wait(300) -- the plugin takes the value as it plays
  local path = T.scratch .. "/quiet.vstpreset"
  T.write_file(path, api.device_call(fx.id, "preset.export", ""))
  fx:set(gain.key, gain.max)
  api.device_load(fx.id, { name = "quiet", factory = path })
  T.near(fx.params[gain.key], gain.min, 1e-3, "the file's state is loaded")
end)

-- Finding a device among hundreds --------------------------------------------------

local function clear_library()
  local lib = paw.fx.library()
  lib.favourites, lib.recent, lib.picks = {}, {}, {}
end

local function kinds_of(list)
  local out = {}
  for i, info in ipairs(list) do
    out[i] = info.kind
  end
  return out
end

test("devices: favourites come first, then the ones used last, and both are kept", function()
  clear_library()
  fresh()
  local track = paw.add_track({ name = "t" })
  paw.fx.toggle_favourite("limiter")
  paw.fx.add(track, "delay")
  paw.fx.add(track, "gain")
  local list = kinds_of(paw.fx.device_list())
  eq(list[1], "limiter", "the favourite first")
  eq(list[2], "gain", "then the one used last")
  eq(list[3], "delay", "then the one before it")
  paw.fx.reload_library()
  eq(paw.fx.is_favourite("limiter"), true, "the favourite is kept in the state directory")
  eq(paw.fx.library().recent[1], "gain", "and so is what was used")
  eq(paw.fx.toggle_favourite("limiter"), false, "marking it again unmarks it")
  clear_library()
end)

test("devices: a match in the name ranks above one in the vendor, and @ words filter", function()
  clear_library()
  local by_vendor = { kind = "a", name = "Plate", vendor = "Acme", format = "clap", category = "effect" }
  local by_name = { kind = "b", name = "Acme Hall", vendor = "Other", format = "lv2", category = "effect" }
  local synth = { kind = "c", name = "Acme Synth", vendor = "Acme", format = "vst3", category = "instrument" }
  eq(paw.fx.rank(by_name, "acme") > paw.fx.rank(by_vendor, "acme"), true, "the name match first")
  eq(paw.fx.rank(synth, "acme @instrument") ~= nil, true, "@instrument keeps instruments")
  eq(paw.fx.rank(by_name, "acme @instrument"), nil, "and leaves effects out")
  eq(paw.fx.rank(by_vendor, "@clap"), 0, "@clap keeps CLAP plugins")
  eq(paw.fx.rank(by_name, "@clap"), nil, "and only them")
  eq(paw.fx.rank(by_vendor, "@acme") ~= nil, true, "@ and a vendor's name keeps that vendor's")
  eq(paw.fx.rank(by_name, "@acme"), nil, "and not another's")
  eq(paw.fx.rank(by_vendor, "@fav"), nil, "@fav keeps favourites only")
end)

test("devices: what was chosen for what was typed comes first the next time", function()
  clear_library()
  fresh()
  local track = paw.add_track({ name = "t" })
  local first = paw.fx.search("a")[1].kind
  local other = first == "delay" and "gain" or "delay"
  paw.fx.add(track, other, { query = "a" })
  eq(paw.fx.search("a")[1].kind, other, "after choosing " .. other .. " for `a`, it comes first for `a`")
  eq(paw.fx.search("@instrument")[1].category, "instrument", "the window's search filters too")
  clear_library()
end)

test("devices: the picker lists favourites first, filters, and marks with Ctrl-f", function()
  clear_library()
  fresh()
  local track = paw.add_track({ name = "t" })
  paw.cursor.set_track(track.id)
  paw.pick("devices", { query = "@instrument" })
  local state = paw.pick.state()
  eq(#state.matches > 0, true, "some instruments")
  for _, line in ipairs(state.matches) do
    eq(line:match("instrument$") ~= nil, true, "only instruments: " .. line)
  end
  T.keys("<Esc>")
  paw.pick("devices", { query = "limiter" })
  T.keys("<C-f>")
  eq(paw.fx.is_favourite("limiter"), true, "Ctrl-f marks the selected device")
  T.keys("<Esc>")
  paw.pick("devices")
  eq(paw.pick.state().item.kind, "limiter", "and it is listed first")
  T.keys("<Esc>")
  local lines = paw.frontend.act.search_devices("limiter")
  eq(lines[1].line:sub(1, 3), "★", "the window's box stars it too")
  clear_library()
end)

-- Wet/dry and gain on every device ------------------------------------------------------

--- The samples of a 16-bit WAV file `paw.render` wrote, as a string.
local function samples(info)
  local data = T.read_file(info.path)
  return data:sub(data:find("data", 1, true) + 8)
end

test("wet/dry: at 0 % a device is not heard at all, at 100 % it is all that is heard", function()
  fresh()
  local t = T.tone("tone", 2)
  local dry = T.render({ bits = 16, tail = 0.1 })
  local boost = t:add_device("gain", { gain = 12 })
  paw.fx.set_wet(boost, 0)
  eq(samples(T.render({ bits = 16, tail = 0.1 })) == samples(dry), true, "0 % wet nulls against the track without it")
  paw.fx.set_wet(boost, 100)
  local wet = T.render({ bits = 16, tail = 0.1 })
  T.near(wet.peak, math.min(1, dry.peak * 10 ^ (12 / 20)), 0.02, "100 % is the device's own output")
  api.device_set_param(boost.id, "fx_gain", -6)
  T.near(
    T.render({ bits = 16, tail = 0.1 }).peak,
    math.min(1, dry.peak * 10 ^ (12 / 20)) / 2,
    0.02,
    "the output gain is applied"
  )
end)

test("quality: a render while paw plays in edit quality is the same, bit for bit, as at full quality", function()
  fresh()
  local t = T.tone("tone", 2, "A5")
  -- Driven hard at 4x: without the oversampling, its harmonics fold back.
  t:add_device("saturation", { drive = 30, oversample = 1 })
  local full = T.render({ bits = 32, tail = 0.1 })
  paw.opt.quality = "edit"
  local edit = T.render({ bits = 32, tail = 0.1 })
  eq(samples(edit) == samples(full), true, "the render plays at full quality")
end)

test("wet/dry: the dry signal is held back by the device's latency", function()
  fresh()
  local t = T.tone("tone", 2)
  -- The limiter looks 5 ms ahead; well under its ceiling it changes nothing
  -- but the timing, so half and half must be the same as all of it.
  local limiter = t:add_device("limiter", { ceiling = 0 })
  local full = T.render({ bits = 16, tail = 0.1 })
  paw.fx.set_wet(limiter, 50)
  local half = T.render({ bits = 16, tail = 0.1 })
  T.near(half.peak, full.peak, 0.003, "no comb filtering from a dry signal 5 ms early")
end)

test("wet/dry: the mix is a parameter like any other: automated, shown, kept", function()
  fresh()
  local t = paw.add_track({ name = "fx" })
  paw.cursor.set_track(t.id)
  local delay = t:add_device("delay")
  local lane = delay:automate("fx_wet")
  lane:set_points({ { 0, 0 }, { 4, 100 } })
  T.near(delay:value_at("fx_wet", 2), 50, 1e-6, "a lane moves it")
  paw.fx.set_wet(delay, 40)
  paw.fx.set_gain(delay, -3)
  local card = paw.frontend.state(-1).devices[1]
  T.near(card.wet, 0.4, 1e-6, "the window's card shows the wet share")
  eq(card.gain, -3, "and the output gain")
  for _, p in ipairs(card.params) do
    eq(paw.fx.host_params[p.key], nil, "not among the parameters: " .. p.key)
  end
  local rows = paw.ui.views:get("devices"):rows()
  eq(rows[#rows - 1].param.key, "fx_wet", "the terminal lists it after the device's own parameters")
  paw.ui.views:get("devices").row = 1
  paw.ui.views:get("devices"):adjust(-10)
  eq(delay.params.fx_wet, 30, "h and l on the device's line change it")
  local path = paw.project.save(T.scratch .. "/wet.json")
  fresh()
  paw.project.load(path)
  eq(paw.tracks()[1]:devices()[1].params.fx_wet, 30, "it is saved with the project")
end)

-- Parameters of large plugins -------------------------------------------------------

test("params: one chosen by name is shown first on the card, and kept with the device", function()
  fresh()
  local t = paw.add_track({ name = "keys" })
  paw.cursor.set_track(t.id)
  t:add_device("synth")
  paw.flush()
  paw.ui.focus("devices")
  paw.ui.views:get("devices").row = 1
  T.keys("f")
  eq(paw.pick.state().title, "Parameters · Synth", "f opens the parameter picker")
  T.keys("reso<CR>")
  local row = paw.ui.views:get("devices"):rows()[paw.ui.views:get("devices").row]
  eq(row.param.key, "resonance", "Enter chooses it in the panel")
  eq(paw.frontend.state(-1).devices[1].params[1].key, "resonance", "and the card shows it first")
  local path = paw.project.save(T.scratch .. "/shown.json")
  fresh()
  paw.project.load(path)
  eq(paw.fx.shown(paw.tracks()[1]:devices()[1])[1], "resonance", "the choice is saved with the project")
end)

test("params: the one last touched shows itself, and :param.last goes to it and automates it", function()
  fresh()
  local t = paw.add_track({ name = "keys" })
  local other = paw.add_track({ name = "other" })
  local synth = t:add_device("synth")
  paw.flush()
  -- What a plugin's own window reports when a knob is turned there.
  paw.emit("param.touched", { device = synth.id, param = "release", from = "editor" })
  eq(paw.fx.last_touched.param, "release", "it is the last touched")
  paw.cursor.set_track(t.id)
  eq(paw.frontend.state(-1).devices[1].params[1].key, "release", "the card shows it first")
  paw.cursor.set_track(other.id)
  paw.commands.exec("param.last automate")
  eq(paw.cursor.track().id, t.id, ":param.last goes to its track")
  local row = paw.ui.views:get("devices"):rows()[paw.ui.views:get("devices").row]
  eq(row.param.key, "release", "and to it in the panel")
  eq(synth:lane("release") ~= nil, true, "`automate` makes its lane")
  synth:set("cutoff", 500)
  paw.wait(20)
  eq(paw.fx.last_touched.param, "cutoff", "a parameter set here is touched too")
end)

test("presets: the window's menu lists those around the one loaded, and All presets… when there are more", function()
  forget_presets("synth")
  fresh()
  local t = paw.add_track({ name = "keys" })
  paw.cursor.set_track(t.id)
  local synth = t:add_device("synth")
  local size = paw.fx.menu_size
  paw.fx.menu_size = 2
  paw.fx.load(synth, "Square lead")
  local menu = paw.frontend.act.preset_menu(synth.id)
  paw.fx.menu_size = size
  eq(#menu, 3, "two presets and the way to the rest")
  eq(menu[3], "All 5 presets…", "the last entry")
  eq(menu[2], "● Square lead  · factory", "the one loaded is among them")
  paw.frontend.act.preset_choose(synth.id, 1)
  eq(paw.fx.current(synth), "Pluck", "an entry loads the preset it names")
end)

-- Copying, moving and reusing devices ------------------------------------------------

local function kinds_on(track)
  local out = {}
  for i, d in ipairs(track:devices()) do
    out[i] = d.kind
  end
  return table.concat(out, ",")
end

test("copy: V selects several devices in the panel; y and p copy them, d cuts them", function()
  fresh()
  local a = paw.add_track({ name = "a" })
  local b = paw.add_track({ name = "b" })
  a:add_device("gain", { gain = 3 })
  a:add_device("delay", { time = 200 })
  paw.cursor.set_track(a.id)
  paw.flush()
  paw.ui.focus("devices")
  paw.ui.views:get("devices").row = 1
  T.keys("V4jy")
  paw.cursor.set_track(b.id)
  paw.flush()
  T.keys("p")
  eq(kinds_on(b), "gain,delay", "both are pasted, in order")
  eq(b:devices()[2].params.time, 200, "with their settings")
  paw.cursor.set_track(a.id)
  paw.flush()
  paw.ui.views:get("devices").row = 1
  T.keys("Vjd")
  eq(kinds_on(a), "delay", "d cuts the selected device")
end)

test("copy: :device.copy_to and :device.move_to take the device to another track", function()
  fresh()
  local a = paw.add_track({ name = "a" })
  local b = paw.add_track({ name = "Bass" })
  a:add_device("delay", { time = 321 })
  paw.cursor.set_track(a.id)
  paw.flush()
  paw.ui.views:get("devices").row = 1
  paw.commands.exec("device.copy_to Bass")
  eq(kinds_on(b), "delay", "a copy is on Bass")
  eq(b:devices()[1].params.time, 321, "with its settings")
  eq(kinds_on(a), "delay", "and the device stays")
  paw.commands.exec("device.move_to 2")
  eq(kinds_on(a), "", "move_to takes it away")
  eq(kinds_on(b), "delay,delay", "to the track at that place")
end)

test(
  "copy: a card dropped on a track's header moves the device there, Ctrl copies, and in the list it reorders",
  function()
    fresh()
    local a = paw.add_track({ name = "a" })
    local b = paw.add_track({ name = "b" })
    local gain = a:add_device("gain")
    local delay = a:add_device("delay")
    local limiter = a:add_device("limiter")
    local A = paw.frontend.act
    A.place_device(limiter.id, 1, false)
    eq(kinds_on(a), "limiter,gain,delay", "dropped above the first card, it goes first")
    A.place_device(limiter.id, 4, false)
    eq(kinds_on(a), "gain,delay,limiter", "dropped below the last, it goes last")
    A.drop_device(gain.id, b.id, true)
    eq(kinds_on(b), "gain", "Ctrl and a header: a copy there")
    eq(kinds_on(a), "gain,delay,limiter", "the device stays")
    A.drop_device(delay.id, b.id, false)
    eq(kinds_on(b), "gain,delay", "a header: the device moves there")
    eq(kinds_on(a), "gain,limiter", "and leaves its track")
  end
)

test(
  "wet/dry: a device whose look-ahead is a parameter: 0 % nulls, 100 % is the device, the dry signal follows its latency",
  function()
    fresh()
    local t = T.tone("tone", 2)
    local dry = T.render({ bits = 16, tail = 0.1 })
    local comp = t:add_device("compressor", { lookahead = 5, threshold = 0 })
    local full = T.render({ bits = 16, tail = 0.1 })
    paw.fx.set_wet(comp, 0)
    -- The render takes the look-ahead off again, so the held-back input nulls.
    eq(samples(T.render({ bits = 16, tail = 0.1 })) == samples(dry), true, "0 % nulls against the track without it")
    paw.fx.set_wet(comp, 50)
    T.near(T.render({ bits = 16, tail = 0.1 }).peak, full.peak, 0.01, "half and half line up: no comb filtering")
    comp:set("lookahead", 2)
    paw.flush()
    paw.wait(50)
    T.near(T.render({ bits = 16, tail = 0.1 }).peak, full.peak, 0.01, "and still when the look-ahead changes")
    paw.fx.set_wet(comp, 100)
    local again = T.render({ bits = 16, tail = 0.1 })
    T.near(again.peak, full.peak, 0.01, "100 % is the device's own output")
  end
)
