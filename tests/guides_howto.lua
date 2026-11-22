-- The how-to guides of the user guide (docs/how-to), each driven with the
-- keys and commands that it gives, on the null backend with its test input
-- and test MIDI port. Each test checks what its guide promises. The lessons
-- of the tutorials are in tests/guides.lua. Loaded by tests/suite.lua with
-- its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

-- The keyboard is a test MIDI port of its own: other tests count what
-- happens to theirs.
local function start()
  fresh()
  api.engine_restart({
    backend = "null",
    test_input = { frequency = 440, level = -12, channels = 2 },
    test_midi = { "Keystation 49" },
  })
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
  T.after(function() api.engine_restart({ backend = "null" }) end)
end

--- Type keys as one undo step, and let what they started finish.
local keys = T.keys

--- A key that also starts longer mappings (`]` and `]]`) runs when the wait
--- for the rest is over, as it does at the keyboard.
local function waited(text)
  local before = paw.opt.timeoutlen
  paw.opt.timeoutlen = 20
  paw.keymap.feed(text)
  paw.wait(150)
  paw.opt.timeoutlen = before
  paw.flush()
  api.undo_checkpoint()
end

local function screen(w, h) return table.concat(api.ui_snapshot(w or 120, h or 40), "\n") end
local function shows(text, what) eq(screen():find(text, 1, true) ~= nil, true, what or ("the screen shows " .. text)) end

--- The loudest meter of a track over `ms`, while `fn` runs at each step.
local function loudest(track, ms, fn)
  local most, deadline = 0, api.now() + ms
  while api.now() < deadline do
    if fn then fn() end
    most = math.max(most, track:meter())
    paw.wait(10)
  end
  return most
end

local function track_named(name)
  for _, t in ipairs(paw.tracks()) do
    if t.name == name then return t end
  end
end

local function names()
  local out = {}
  for _, t in ipairs(paw.tracks()) do
    out[#out + 1] = t.name
  end
  return table.concat(out, " ")
end

local function cursor_track() return paw.cursor.track() and paw.cursor.track().name end

local function notes(clip)
  local out = {}
  for _, n in ipairs(clip:notes()) do
    out[#out + 1] = string.format("%d@%g+%g v%d", n.pitch, n.start, n.length, n.velocity)
  end
  table.sort(out)
  return table.concat(out, " ")
end

--- Load a bundled extension as the guide says. Unless `keep`, unload it
--- after the test: the keys and views that it adds (undotree maps `\`) are
--- not there for the other tests. The doctor stays, as its own tests leave
--- it: its key bar outlives an unload.
local function load_bundled(name, keep)
  if not paw.ext.loaded[name] then
    keys(":ext.load " .. name .. "<CR>")
    if not keep then T.after(function() paw.ext.unload(name, { force = true }) end) end
  end
  eq(paw.ext.loaded[name] ~= nil, true, name .. " is loaded")
end

-- Install and configure ----------------------------------------------------------

test("guide: start paw the first time and hear sound", function()
  start()
  -- `paw doctor` from the shell prints a report of the checks that need nobody.
  local out = T.scratch .. "/guide-doctor.txt"
  local pipe = io.popen("readlink /proc/" .. api.env().pid .. "/exe")
  local binary = pipe:read("*l")
  pipe:close()
  os.execute(
    string.format(
      "XDG_STATE_HOME='%s/guide-state' '%s' doctor --clean --no-plugins --audio null --only system > '%s' 2>/dev/null",
      T.scratch,
      binary,
      out
    )
  )
  local report = T.read_file(out)
  eq(report:find("The sound system", 1, true) ~= nil, true, "the report has the sound system")
  eq(report:find("null", 1, true) ~= nil, true, "and names the backend")
  -- :checkhealth audio.
  keys(":checkhealth audio<CR>")
  shows("the null audio backend: nothing is heard", "the health check says that nothing is heard")
  shows("WARN", "as a warning")
  keys("q")
  eq(paw.ui.float, nil, "q closes the window")
  -- The test tone: on the null backend the check runs and says why it is skipped.
  load_bundled("doctor", true)
  paw.opt.doctor_dir = T.scratch .. "/doctor"
  keys(":doctor output<CR>")
  local doctor = require("doctor")
  local limit = api.now() + 20000
  while doctor.running() and api.now() < limit do
    paw.wait(20)
  end
  local result = doctor.run().done[1]
  eq(result.id, "output", "the output check ran")
  eq(
    result.status .. ": " .. result.summary,
    "skip: the null backend makes no sound to listen to",
    "and on the null backend says so"
  )
  keys("q")
  paw.ui.focus("arrange")
  -- An instrument.
  keys("o")
  keys("a")
  keys("synth<CR>")
  local t = paw.tracks()[1]
  eq(t:devices()[1].kind, "synth", "the synth is on the track")
  keys("i<CR>")
  keys("4l")
  keys("<Esc>")
  local clip = t:clips()[1]
  eq(clip ~= nil and notes(clip), "60@0+1 v100", "one note of one beat in a new clip")
  keys("gs")
  keys("<Space><Space>")
  local heard = loudest(t, 600)
  T.stop()
  eq(heard > 0.01, true, "the meter of the track moves")
end)

test("guide: connect a MIDI keyboard", function()
  start()
  keys(":midi.inputs<CR>")
  shows("Keystation 49", "the port is in the list")
  shows("open", "and open")
  keys("<Esc>")
  paw.ui.close()
  keys("o")
  keys("a")
  keys("synth<CR>")
  local t = paw.tracks()[1]
  local function play()
    -- The note before dies away first.
    local quiet = api.now() + 3000
    while t:meter() > 0.0005 and api.now() < quiet do
      paw.wait(20)
    end
    return loudest(
      t,
      300,
      function() paw.midi.inject({ type = "note_on", pitch = 60, velocity = 100, port = "Keystation 49" }) end
    )
  end
  local function release()
    paw.midi.inject({ type = "note_off", pitch = 60, port = "Keystation 49" })
    paw.wait(100)
  end
  eq(play() > 0.01, true, "the selected track plays the keyboard, not armed")
  release()
  local other = paw.add_track({ name = "Other" })
  keys("j")
  eq(paw.cursor.track_id(), other.id, "j goes to the next track")
  eq(play() < 0.001, true, "and the keyboard no longer plays the first")
  release()
  keys("k")
  other.armed = true
  paw.flush()
  eq(play() < 0.001, true, "with a track armed, only the armed tracks play the keyboard")
  release()
  other.armed = false
  keys(":set midi_follows_selection false<CR>")
  T.after(function() paw.opt.midi_follows_selection = true end)
  eq(play() < 0.001, true, "turned off, the selected track does not play the keyboard")
  release()
  keys("r")
  eq(t.armed, true, "r arms the track")
  eq(play() > 0.01, true, "the armed track plays the keyboard")
  release()
  keys("r")
  keys("<A-i>")
  eq(t.monitor, true, "<A-i> switches the monitor on")
  eq(play() > 0.01, true, "and the track plays the keyboard")
  release()
  keys("I")
  keys("Keystation<CR>")
  eq(t.midi_input and t.midi_input.port, "Keystation 49", "I takes one port")
  keys(":track.midi Keystation ch=1<CR>")
  eq(
    t.midi_input.port .. " " .. tostring(t.midi_input.channel),
    "Keystation 49 1",
    ":track.midi takes a port and a channel"
  )
  keys(":midi.select Keystation<CR>")
  T.after(function() paw.midi.select(nil) end)
  eq(play() > 0.01, true, "the selected port still plays")
  release()
end)

test("guide: use your own plugins", function()
  start()
  local rescanned = paw.cmd("plugins.rescan", { "nothing-of-that-name" })
  eq(rescanned == nil or rescanned ~= false, true, ":plugins.rescan with a name runs")
  paw.add_track({ name = "Guitar" })
  paw.cursor.set_track(paw.tracks()[1])
  -- A built-in device stands for the plugin: the list and the command are the same.
  keys("a")
  keys("reverb<CR>")
  eq(paw.tracks()[1]:devices()[1].kind, "reverb", "a part of the name in the list of devices")
  keys(":device.add delay<CR>")
  eq(paw.tracks()[1]:devices()[2].kind, "delay", ":device.add takes a part of the name")
  load_bundled("doctor", true)
  local before = paw.opt.doctor_plugins
  T.after(function() paw.opt.doctor_plugins = before end)
  keys(':lua paw.opt.doctor_plugins = { "surge" }<CR>')
  eq(paw.inspect(paw.opt.doctor_plugins), paw.inspect({ "surge" }), "the plugins for the doctor")
end)

test("guide: lower the latency", function()
  start()
  keys(":audio<CR>")
  shows("frames", "the top line gives the block")
  keys("128 frames<CR>")
  -- The device starts again with the new block, and says its block (0
  -- until then) at its first callback.
  T.until_(function() return api.engine_get().block == 128 end, "the block chosen in the list")
  keys(":engine.status<CR>")
  local said = paw.messages and paw.messages()[#paw.messages()] or nil
  eq(said == nil or tostring(said.text or said):find("xruns", 1, true) ~= nil, true, ":engine.status gives the xruns")
  keys(":audio.buffer 256<CR>")
  T.until_(function() return api.engine_get().block == 256 end, ":audio.buffer to set it")
  keys(":audio.buffer 0<CR>")
end)

-- Tracks and instruments -----------------------------------------------------------

test("guide: add a track with a virtual instrument", function()
  start()
  keys("o")
  keys("grn")
  keys("<C-u>Bass<CR>")
  eq(names(), "Bass", "the track and its name")
  keys("a")
  shows("Synth", "the instruments are in the list")
  keys("synth<CR>")
  local t = track_named("Bass")
  local d = t:devices()[1]
  eq(d.kind, "synth", "the synth")
  keys("<Space>dd")
  eq(paw.ui.focused, "devices", "the device panel")
  keys("c")
  keys("pluck<CR>")
  eq(api.device_get(d.id).params.cutoff, 3000, "the preset Pluck")
  keys("]p")
  eq(api.device_get(d.id).params.cutoff, 6000, "]p the next preset")
  keys("<C-w>p")
  eq(paw.ui.focused, "arrange", "back in the arrange view")
  keys("i<CR>")
  keys("4l")
  keys("<Esc>")
  eq(notes(t:clips()[1]), "60@0+1 v100", "a note of one beat")
  keys("gs<Space><Space>")
  local heard = loudest(t, 600)
  T.stop()
  eq(heard > 0.01, true, "it plays")
  keys(":device.add drums<CR>")
  eq(t:devices()[2].kind, "drums", ":device.add drums")
end)

test("guide: add an audio track for a microphone or a guitar", function()
  start()
  keys("o")
  keys("grn")
  keys("<C-u>Guitar<CR>")
  local t = track_named("Guitar")
  keys("I")
  keys("test signal 1<CR>")
  eq(t.input, "1", "the first channel of the input")
  shows("test signal", "the header shows the input")
  eq(loudest(t, 300) < 0.001, true, "not heard yet")
  keys("<A-i>")
  eq(t.monitor, true, "the monitor is on")
  eq(loudest(t, 300) > 0.01, true, "the input is heard through the track")
  keys(":track.input 1/2<CR>")
  eq(t.input, "1/2", ":track.input takes a pair")
  keys("a")
  keys("reverb<CR>")
  eq(t:devices()[1].kind, "reverb", "an effect on the track")
  keys("r")
  eq(t.armed, true, "r arms it")
  keys("r")
end)

test("guide: name, color, reorder and group tracks", function()
  start()
  keys("o")
  keys("o")
  keys("o")
  keys("gg")
  keys("grn")
  keys("<C-u>Kick<CR>")
  keys("j")
  keys("grn")
  keys("<C-u>Snare<CR>")
  keys("j")
  keys("grn")
  keys("<C-u>Bass<CR>")
  eq(names(), "Kick Snare Bass", "named")
  keys("grC")
  keys("coral<CR>")
  eq(track_named("Bass").color, "#e0605a", "colored coral")
  keys("grC")
  keys("none<CR>")
  eq(track_named("Bass").color, nil, "none gives the color of the theme again")
  keys("<A-k>")
  eq(names(), "Kick Bass Snare", "<A-k> moves it up")
  keys("<A-j>")
  eq(names(), "Kick Snare Bass", "<A-j> moves it down")
  keys("gg")
  keys("2<A-j>")
  eq(names(), "Snare Bass Kick", "a count moves it more places")
  keys("u")
  keys("G")
  keys("gg")
  keys("Vj")
  keys("<Space>tg")
  keys("<C-u>Drums<CR>")
  local drums = track_named("Drums")
  eq(drums ~= nil, true, "the group")
  eq(paw.groups.of(track_named("Kick")), drums.id, "Kick is in it")
  eq(paw.groups.of(track_named("Snare")), drums.id, "and Snare")
  local rows = #paw.groups.rows()
  paw.cursor.set_track(drums)
  keys("za")
  eq(#paw.groups.rows(), rows - 2, "za folds the group")
  keys("za")
  eq(#paw.groups.rows(), rows, "and opens it")
  paw.cursor.set_track(track_named("Bass"))
  keys(":track.into Drums<CR>")
  eq(paw.groups.of(track_named("Bass")), drums.id, ":track.into puts a track into the group")
  keys("<Space>tG")
  eq(paw.groups.of(track_named("Bass")), nil, "Space tG takes it out")
end)

test("guide: change the sound of an instrument", function()
  start()
  local t = paw.add_track({ name = "Lead" })
  local d = t:add_device("synth")
  paw.cursor.set_track(t)
  api.undo_checkpoint()
  keys("<Space>dd")
  eq(paw.ui.focused, "devices", "the device panel")
  -- To the cutoff: the rows after the heading are the parameters in order.
  local rows = { "wave", "attack", "decay", "sustain", "release", "cutoff" }
  keys(#rows .. "j")
  local before = api.device_get(d.id).params.cutoff
  keys("+")
  eq(api.device_get(d.id).params.cutoff ~= before, true, "+ changes the parameter")
  keys("c")
  keys("<C-u>800<CR>")
  eq(api.device_get(d.id).params.cutoff, 800, "c types its value")
  keys("x")
  eq(api.device_get(d.id).params.cutoff, before, "x gives the default again")
  keys("gg")
  keys("c")
  keys("sub bass<CR>")
  eq(api.device_get(d.id).params.cutoff, 400, "a preset by a part of its name")
  keys("]p")
  eq(api.device_get(d.id).params.cutoff, 900, "]p the next")
  keys("[p")
  eq(api.device_get(d.id).params.cutoff, 400, "[p the one before")
  shows("Sub bass", "the name of the preset shows")
  paw.opt.presets_dir = T.scratch .. "/guide-presets"
  keys("<Space>dw")
  keys("<C-u>My bass<CR>")
  keys("c")
  shows("My bass", "the saved preset is in the list")
  keys("<Esc>")
end)

--- The plugin of a package that a variable names (`PAW_TEST_TONE3000`), when
--- the run gives the plugins a scratch HOME: they write to ~/.config.
local function amp_plugin(var, format, name)
  local pkg = os.getenv(var)
  if not pkg or pkg == "" then return nil, "skipped: " .. var .. " names no package" end
  local user, home = os.getenv("USER") or "", nil
  for line in (T.read_file("/etc/passwd")):gmatch("[^\n]+") do
    local n, dir = line:match("^([^:]*):[^:]*:[^:]*:[^:]*:[^:]*:([^:]*):")
    if n == user then home = dir end
  end
  if not home or (os.getenv("HOME") or ""):gsub("/+$", "") == home then
    return nil, "skipped: the plugin would write to the home folder"
  end
  for _, info in ipairs(paw.device_types()) do
    if info.format == format and info.name == name then return info.kind, pkg end
  end
  return nil, "skipped: " .. name .. " not found"
end

test("guide: find and change a setting inside a plugin", function()
  local kind
  for _, info in ipairs(paw.device_types()) do
    if info.format == "clap" and info.name == "Compressor Mono" then kind = info.kind end
  end
  if not kind then return "skipped: LSP Compressor Mono (CLAP) not found" end
  start()
  load_bundled("plugstate")
  local function said() return paw.ui.messages[#paw.ui.messages].text end
  local t = paw.add_track({ name = "Bass" })
  t:add_device("synth")
  t:add_clip({ start = 0, length = 4, notes = { { pitch = "A2", start = 0, length = 4 } } })
  local comp = t:add_device(kind)
  paw.flush()
  api.undo_checkpoint()
  paw.cursor.set_track(t.id)
  -- See the state of the plugin.
  paw.ui.focus("devices")
  paw.fx.select(comp.id)
  keys(":plugstate.tree<CR>")
  eq(said():find("LSP", 1, true) ~= nil, true, "the first line names the framework: " .. said())
  keys(":plugstate.tree /LSP/Parameters<CR>")
  eq(said():find("@g_out = 1", 1, true) ~= nil, true, "one part of the tree: " .. said())
  keys(":plugstate.info<CR>")
  eq(said():find("state: LSP", 1, true) ~= nil, true, ":plugstate.info names it: " .. said())
  -- Find where it keeps a setting: a change as from its window.
  keys(":plugstate.mark<CR>")
  api.device_set_param(comp.id, "output_gain", -6)
  -- The plugin takes the value in its next block.
  T.until_(
    function() return require("plugstate.juceplugins").open(comp.id):get("/LSP/Parameters@g_out") ~= 1 end,
    "the plugin to take the value"
  )
  keys(":plugstate.changes<CR>")
  eq(said():find("set    /LSP/Parameters@g_out: 1 → ", 1, true) ~= nil, true, "the path that changed: " .. said())
  --- The value at a path of the plugin's state once it is `want` (two
  --- seconds at most): what paw loads reaches the plugin a moment later.
  local function value(id, want)
    local v
    for _ = 1, 100 do
      paw.flush()
      v = require("plugstate.juceplugins").open(id):get("/LSP/Parameters@g_out")
      if want == nil or v == want then return v end
      api.sleep(20)
    end
    return v
  end
  keys("u")
  eq(value(comp.id, 1), 1, "u: the value of before")
  -- Change it from paw, and undo.
  keys(":plugstate.path /LSP/Parameters@g_out 0.5<CR>")
  eq(value(comp.id, 0.5), 0.5, "the plugin takes the value: " .. said())
  keys(":plugstate.path /LSP/Parameters@g_out<CR>")
  eq(said(), "/LSP/Parameters@g_out = 0.5", "a value by its path")
  keys("u")
  eq(value(comp.id, 1), 1, "u returns to the value before")
  -- Keep the change as a preset, and load it on another track.
  local home = os.getenv("HOME")
  local file = T.scratch .. "/quiet"
  keys(":plugstate.mark<CR>")
  api.device_set_param(comp.id, "output_gain", -6)
  paw.flush()
  keys(":plugstate.preset_write " .. file .. "<CR>")
  eq(io.open(file .. ".jucepreset") ~= nil, true, "the preset file: " .. said())
  local t2 = paw.add_track({ name = "Keys" })
  local comp2 = t2:add_device(kind)
  paw.flush()
  paw.cursor.set_track(t2.id)
  paw.fx.select(comp2.id)
  keys(":plugstate.load " .. file .. ".jucepreset<CR>")
  local loaded = value(comp2.id, value(comp.id))
  eq(loaded < 1, true, "the preset loads into the other plugin: " .. tostring(loaded))
  paw.cursor.beat = 2
  keys(":plugstate.at " .. file .. ".jucepreset<CR>")
  eq(said():find("on its state lane", 1, true) ~= nil, true, "the preset at a point: " .. said())
  eq(home, os.getenv("HOME"), "HOME stays")
end)

test("guide: switch amp models and presets from paw", function()
  local kind, pkg = amp_plugin("PAW_TEST_TONE3000", "clap", "TONE3000")
  if not kind then return pkg end
  start()
  load_bundled("plugstate")
  local plugstate = require("plugstate")
  local t = paw.add_track({ name = "Guitar" })
  t:add_device("synth")
  t:add_clip({ start = 0, length = 4, notes = { { pitch = "A2", start = 0, length = 4 } } })
  local amp = t:add_device(kind)
  paw.flush()
  paw.cursor.set_track(t)
  api.undo_checkpoint()
  local factory = pkg .. "/share/tone3000/factory-presets/"
  keys("<Space>dd")
  eq(paw.ui.focused, "devices", "the device panel")
  keys("]m")
  eq(plugstate.slot(amp.id).value, factory .. "Ampeg Bass Drive.t3kpreset", "]m loads the next preset")
  shows("Ampeg Bass Drive", "the message line shows its name")
  keys("]m")
  keys("[m")
  eq(plugstate.slot(amp.id).value, factory .. "Ampeg Bass Drive.t3kpreset", "[m the preset before")
  keys("3]m")
  eq(plugstate.slot(amp.id).value, factory .. "Marshall Bluesbreaker.t3kpreset", "a count skips more")
  keys("u")
  eq(plugstate.slot(amp.id).value, factory .. "Ampeg Bass Drive.t3kpreset", "u: the preset before plays again")
  keys(":plugstate.load bogner<CR>")
  eq(amp:get().meta.preset, "Bogner Fullstack", "a preset by words of its name")
  -- A model into a block: one of a factory preset, written out.
  local t3k, juce = require("plugstate.tone3000"), require("plugstate.juce")
  local preset = t3k.read_preset(factory .. "Stereo Fuzz.t3kpreset")
  local cached = juce.child(juce.child(t3k.blocks(preset)[1].block, "ModelCache"), "CachedModel")
  local nam = T.scratch .. "/deluxe.nam"
  T.write_file(nam, juce.get(cached, "data").binary)
  keys(":plugstate.info<CR>")
  keys(":messages<CR>")
  shows("block2 (Block 2", ":messages lists the blocks")
  keys("<Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("devices")
  keys(":plugstate.load slot=block2 " .. nam .. "<CR>")
  eq(plugstate.slot(amp.id, "block2").value, nam, "the block plays the model")
  os.remove(nam)
  eq(plugstate.slot(amp.id, "block2").label, "Block 2 (deluxe)", "TONE3000 keeps the model when the file is gone")
  keys("\\s")
  keys(":plugstate.load ampeg<CR>")
  keys("\\s")
  keys("]v")
  eq(plugstate.current(amp.id), "A", "]v switches to the other snapshot")
  eq(amp:get().meta.preset, "A", "with its sound")
end)

-- Edit and arrange ---------------------------------------------------------------

local function clip_layout(t)
  local out = {}
  for _, c in ipairs(api.clip_list(t.id)) do
    out[#out + 1] = string.format("%s@%g+%g", c.name, c.start, c.length)
  end
  return table.concat(out, " ")
end

test("guide: move, copy, split and trim clips", function()
  start()
  local a = paw.add_track({ name = "A" })
  local b = paw.add_track({ name = "B" })
  a:add_clip({ name = "v", start = 0, length = 4 })
  paw.cursor.set_track(a)
  paw.cursor.set_beat(0)
  paw.opt.grid = 1
  api.undo_checkpoint()
  keys("L")
  eq(clip_layout(a), "v@1+4", "L moves it a step later")
  keys("H")
  eq(clip_layout(a), "v@0+4", "H earlier")
  keys("4L")
  eq(clip_layout(a), "v@4+4", "4L four steps")
  keys("u")
  keys("u")
  keys("u")
  keys("0")
  keys("yic")
  paw.cursor.set_beat(8)
  keys("P")
  eq(clip_layout(a), "v@0+4 v@8+4", "P puts the copy at the cursor")
  keys("u")
  keys("0")
  keys("&")
  eq(clip_layout(a), "v@0+4 v@4+4", "& repeats the clip after itself")
  keys("&")
  eq(clip_layout(a), "v@0+4 v@4+4 v@8+4", "& again, the next copy")
  keys("u")
  keys("u")
  keys("0")
  keys("4&")
  eq(clip_layout(a), "v@0+4 v@4+4 v@8+4 v@12+4 v@16+4", "4& puts four copies after the clip")
  keys("u")
  paw.cursor.set_beat(2)
  keys("S")
  eq(clip_layout(a), "v@0+2 v@2+2", "S splits at the cursor")
  keys("u")
  keys("0")
  keys("<A-h>")
  eq(clip_layout(a), "v@0+3", "<A-h> shortens the end")
  keys("<A-l>")
  keys("<A-l>")
  eq(clip_layout(a), "v@0+5", "<A-l> lengthens it")
  keys("u")
  keys("u")
  keys("u")
  paw.cursor.set_beat(1)
  keys("S")
  keys("h")
  keys("x")
  eq(clip_layout(a), "v@1+3", "S h x removes the start")
  keys("u")
  keys("u")
  keys("0")
  keys("x")
  eq(clip_layout(a), "", "x cuts the clip")
  keys("j")
  keys("P")
  eq(clip_layout(b), "v@0+4", "and P puts it on a different track")
end)

test("guide: change the velocity, length and pitch of notes, and quantize them", function()
  start()
  local t = paw.add_track({ name = "Keys" })
  t:add_device("synth")
  local c = t:add_clip({
    name = "a",
    start = 0,
    length = 4,
    notes = {
      { pitch = 60, start = 0, length = 1 },
      { pitch = 64, start = 1, length = 1 },
      { pitch = 67, start = 2, length = 1 },
    },
  })
  paw.cursor.set_track(t)
  paw.cursor.set_beat(0)
  api.undo_checkpoint()
  keys("<CR>")
  eq(paw.ui.focused, "pianoroll", "Enter opens the piano roll")
  keys("0")
  waited("]")
  eq(notes(c), "60@0+1 v110 64@1+1 v100 67@2+1 v100", "] louder")
  waited("[")
  eq(notes(c), "60@0+1 v100 64@1+1 v100 67@2+1 v100", "[ softer")
  local step = paw.opt.note_grid
  keys("<A-l>")
  eq(notes(c), string.format("60@0+%g v100 64@1+1 v100 67@2+1 v100", 1 + step), "<A-l> longer by a step")
  keys("<A-h>")
  keys("+")
  eq(notes(c), "61@0+1 v100 64@1+1 v100 67@2+1 v100", "+ a semitone up")
  keys("-")
  keys("12+")
  eq(notes(c), "64@1+1 v100 67@2+1 v100 72@0+1 v100", "12+ an octave")
  keys("u")
  keys("w")
  eq(paw.ui.views.pianoroll.beat, 1, "w goes to the next note")
  keys("K")
  keys("<Esc>")
  paw.ui.close()
  keys("vie")
  waited("]")
  eq(notes(c), "60@0+1 v110 64@1+1 v110 67@2+1 v110", "vie ] every note louder")
  eq(paw.keymap.mode, "n", "the change ends the selection")
  keys("gv12<C-a>")
  eq(notes(c), "72@0+1 v110 76@1+1 v110 79@2+1 v110", "gv selects them again, 12<C-a> transposes")
  keys("gv5<C-x>")
  keys("<Esc>")
  eq(notes(c), "67@0+1 v110 71@1+1 v110 74@2+1 v110", "gv 5<C-x> down")
  -- Quantize.
  c:set_notes({
    { pitch = 60, start = 0.1, length = 0.9 },
    { pitch = 64, start = 1.05, length = 1 },
    { pitch = 67, start = 2.2, length = 1 },
  })
  paw.opt.note_grid = 0.25
  api.undo_checkpoint()
  keys(":notes.quantize<CR>")
  eq(notes(c), "60@0+0.9 v100 64@1+1 v100 67@2.25+1 v100", ":notes.quantize moves the starts")
  keys("u")
  keys(":notes.quantize 50<CR>")
  eq(notes(c), "60@0.05+0.9 v100 64@1.025+1 v100 67@2.225+1 v100", "half of the distance")
  keys("u")
  keys("=ie")
  eq(notes(c), "60@0+1 v100 64@1+1 v100 67@2.25+1 v100", "=ie the starts and the lengths")
  keys("]g")
  eq(paw.opt.note_grid, 0.5, "]g a coarser grid")
  keys("[g")
  eq(paw.opt.note_grid, 0.25, "[g a finer grid")
  keys("<C-w>p")
end)

test("guide: loop a part of the song while you work", function()
  start()
  local t = paw.add_track({ name = "Keys" })
  t:add_clip({ name = "a", start = 4, length = 8 })
  paw.cursor.set_track(t)
  paw.cursor.set_beat(5)
  paw.opt.grid = 1
  api.undo_checkpoint()
  local tr = paw.transport
  local function loop() return string.format("%g-%g %s", tr.loop_start, tr.loop_end, tostring(tr.loop_enabled)) end
  keys("glic")
  eq(loop(), "4-12 true", "glic loops the clip")
  shows("loop 2–3", "the status line gives its bars")
  keys("gL")
  eq(loop(), "4-12 false", "gL turns it off")
  keys("gL")
  eq(loop(), "4-12 true", "and on, over the same part")
  paw.cursor.set_beat(16)
  keys("glib")
  eq(loop(), "16-20 true", "glib the bar")
  keys("gl2ib")
  eq(loop(), "16-24 true", "gl2ib two bars")
  paw.cursor.set_beat(0)
  keys("vllllgl")
  keys("<Esc>")
  eq(loop(), "0-4 true", "a range in visual mode")
  paw.markers.add(8, "Chorus", { length = 8 })
  api.undo_checkpoint()
  keys(":region.loop Chorus<CR>")
  eq(loop(), "8-16 true", ":region.loop")
  tr.loop_start, tr.loop_end = 24, 32
  keys(":region Bridge<CR>")
  eq(paw.markers.region("Bridge").beat, 24, ":region makes a region over the loop")
  paw.cursor.set_beat(40)
  keys("vllll<Space>rn")
  keys("Outro<CR>")
  local outro = paw.markers.region("Outro")
  eq(
    outro and outro.beat .. "-" .. outro.beat + outro.length,
    "40-44",
    "Space rn makes a region over the selection, with the name typed"
  )
  paw.cursor.set_beat(41)
  keys("<Space>rl")
  eq(loop(), "40-44 true", "Space rl loops the region the cursor is in")
  -- Fast, so that the playhead comes round the loop in a moment.
  keys(":region.loop Chorus<CR>")
  paw.project.tempo = 999
  paw.transport.seek(8)
  keys("<Space><Space>")
  local passed, limit = 0, api.now() + 3000
  local last = tr.position
  while api.now() < limit and passed < 2 do
    if tr.position < last then passed = passed + 1 end
    last = tr.position
    paw.wait(5)
  end
  tr.stop()
  eq(passed, 2, "the playhead returns to the start of the loop")
end)

--- The styles of the loop's band that the arrange view writes to its ruler
--- (row 0 of its buffer), by name: what both frontends are sent in the scene.
local function ruler_styles(width, height)
  local Buf = paw.ui.Buf
  local fill = Buf.fill
  local found = {}
  Buf.fill = function(self, x, y, w, h, char, style)
    if type(style) == "string" and style:find("^RulerLoop") then found[style] = true end
    return fill(self, x, y, w, h, char, style)
  end
  local ok, err = pcall(api.ui_view_snapshot, "arrange", width, height)
  Buf.fill = fill
  if not ok then error(err, 0) end
  return found
end

test("looping: v then gl sets the loop and says so; :loop works; the ruler and the status line show it", function()
  start()
  local t = paw.add_track({ name = "Keys" })
  t:add_clip({ name = "a", start = 16, length = 16 })
  paw.cursor.set_track(t)
  paw.opt.grid = 1
  local tr = paw.transport
  local function loop() return string.format("%g-%g %s", tr.loop_start, tr.loop_end, tostring(tr.loop_enabled)) end
  local function said() return paw.ui.messages[#paw.ui.messages].text end
  -- Bars 5 to 8 are beats 16 to 32.
  paw.cursor.set_beat(16)
  keys("v4W")
  keys("gl")
  eq(loop(), "16-32 true", "v over bars 5 to 8, gl: the loop is bars 5 to 8 and on")
  eq(said(), "loop: bars 5 to 8, on", "and the message says so")
  eq(next(ruler_styles(120, 30)), "RulerLoop", "the ruler draws the band bright")
  shows("loop 5–8", "the status line shows the bars while it is on")
  tr.play()
  eq(ruler_styles(120, 30).RulerLoop, true, "bright while the song plays")
  tr.stop()
  keys("gL")
  eq(said(), "loop: off", "gL says that it is off")
  local off = ruler_styles(120, 30)
  eq(off.RulerLoopOff and not off.RulerLoop, true, "the band stays on the ruler, dim")
  eq(screen():find("loop 5–8", 1, true), nil, "the status line shows no loop while it is off")
  -- Also while the song plays and records.
  tr.play()
  eq(ruler_styles(120, 30).RulerLoopOff, true, "dim while the song plays")
  tr.stop()
  t.armed = true
  tr.recording = true
  eq(tr.recording, true, "the song records")
  eq(ruler_styles(120, 30).RulerLoopOff, true, "dim while it records")
  tr.stop()
  t.armed = false
  keys("gL")
  eq(ruler_styles(120, 30).RulerLoop, true, "bright again when it is back on")
  -- gl with a motion.
  paw.cursor.set_beat(20)
  keys("glic")
  eq(loop(), "16-32 true", "glic loops the clip")
  paw.markers.add(40, "Chorus", { length = 8 })
  paw.cursor.set_beat(42)
  keys("glar")
  eq(loop(), "40-48 true", "glar loops the region")
  -- The command line.
  keys(":5,9loop<CR>")
  eq(loop(), "16-36 true", ":5,9loop")
  eq(said(), "loop: bars 5 to 9, on", "and says so")
  keys(":loop off<CR>")
  eq(loop(), "16-36 false", ":loop off")
  keys(":loop on<CR>")
  eq(loop(), "16-36 true", ":loop on")
  paw.cursor.set_beat(8)
  tr.loop_enabled = false
  paw.cursor.set_beat(8)
  keys("v4W<Esc>:'<,'>loop<CR>")
  eq(loop(), "8-24 true", ":'<,'>loop loops the selection")
  tr.loop_enabled = false
end)

test("guide: change the tempo and the time signature", function()
  start()
  local t = paw.add_track({ name = "T" })
  t:add_clip({ start = 0, length = 64 })
  paw.cursor.set_track(t)
  api.undo_checkpoint()
  keys("grt")
  keys("<C-u>96<CR>")
  eq(paw.project.tempo, 96, "grt types the tempo")
  shows("96 bpm", "the status line shows it")
  keys(":tempo 100<CR>")
  eq(paw.project.tempo, 100, ":tempo")
  keys(":timesig 6/8<CR>")
  eq(table.concat({ paw.tempo.signature_at(0) }, "/"), "6/8", ":timesig at the start")
  keys(":timesig 4/4<CR>")
  keys(":tempo 140 at 17<CR>")
  eq(paw.tempo.at(64), 140, "a change at bar 17")
  eq(paw.tempo.at(63), 100, "and not before it")
  keys(":timesig 7/8 at 9<CR>")
  eq(table.concat({ paw.tempo.signature_at(paw.tempo.bar_of and 40 or 40) }, "/"), "7/8", "7/8 from bar 9")
  paw.cursor.set_beat(70)
  keys(":tempo.remove<CR>")
  eq(paw.tempo.at(70), 100, ":tempo.remove after the change removes it")
  keys(":tempo.list<CR>")
  paw.ui.close()
  keys("<Space>Tt")
  eq(paw.ui.message.text, "tap again in time", "Space Tt is the first tap")
  for _ = 1, 3 do
    paw.wait(500)
    keys("<Space>Tt")
  end
  local near_bpm = paw.tempo.at(70)
  eq(near_bpm > 80 and near_bpm < 160, true, "Space Tt on each beat: about 120 bpm, not " .. near_bpm)
end)

test("guide: undo, and return to an earlier state", function()
  start()
  local t = paw.add_track({ name = "Keys" })
  t:add_clip({ name = "a", start = 0, length = 4 })
  paw.cursor.set_track(t)
  paw.cursor.set_beat(0)
  paw.opt.grid = 1
  api.undo_checkpoint()
  local function at() return api.clip_list(t.id)[1].start end
  keys("3L")
  keys("u")
  eq(at(), 0, "u undoes")
  keys("<C-r>")
  eq(at(), 3, "<C-r> redoes")
  keys("u")
  keys("2L")
  eq(at(), 2, "a new branch")
  local states = #api.undo_tree().states
  keys("<Space>fu")
  shows("Undo history", "the list of states")
  -- The newest first: the second line is the state of the other branch.
  keys("<C-n><CR>")
  eq(at(), 3, "Enter returns to the state of the first branch")
  eq(#api.undo_tree().states, states, "the return is not a change")
  load_bundled("undotree")
  keys("<Space>pu")
  eq(paw.ui.focused, "undotree", "Space pu opens the tree")
  paw.ui.close()
  paw.ui.focus("arrange")
  keys("g-")
  keys("g+")
end)

-- Find things ----------------------------------------------------------------------

test("guide: find a command or a key you forgot", function()
  start()
  paw.add_track({ name = "T" })
  paw.cursor.set_beat(0)
  paw.transport.seek(8)
  keys("?")
  shows("Keys · arrange", "? lists the keys of the view")
  keys("playhead start")
  paw.wait(200)
  shows("gs", "the key that moves the playhead to the start")
  keys("<CR>")
  eq(paw.transport.position, 0, "Enter does what the key does")
  paw.transport.seek(8)
  keys("<Space>fk")
  keys("playhead start")
  paw.wait(200)
  keys("<CR>")
  eq(paw.transport.position, 0, "Space fk is the same list")
  keys("<Space>f:")
  shows("Commands", "Space f: lists the commands")
  keys("metronome")
  paw.wait(200)
  keys("<CR>")
  eq(paw.transport.metronome, true, "a command found by a part of its name")
  keys(":transport.metronome<CR>")
  local done = paw.commands.complete("tem")
  eq(#done > 0, true, "Tab completes the name of a command")
  keys(":help gl<CR>")
  local win, buf, text, at = paw.textbuf.here()
  eq(win ~= nil and buf.name:match("^help://") ~= nil, true, ":help opens a page of help")
  eq(text:line(at.row):find("gl", 1, true) ~= nil, true, "at the line of the key")
  keys(":q<CR>")
  paw.ui.focus("arrange")
  keys(":helpgrep loop<CR>")
  eq(#paw.qf.current().entries > 0, true, ":helpgrep fills the quickfix list")
end)

test("guide: find a track, a clip or a marker by name", function()
  start()
  local a = paw.add_track({ name = "Bass" })
  local b = paw.add_track({ name = "Strings" })
  b:add_clip({ name = "verse 1", start = 8, length = 4 })
  b:add_clip({ name = "verse 2", start = 24, length = 4 })
  paw.markers.add(16, "Chorus")
  paw.markers.add(32, "Outro")
  paw.cursor.set_track(a)
  paw.cursor.set_beat(0)
  api.undo_checkpoint()
  keys("/verse<CR>")
  eq(cursor_track() .. " " .. paw.cursor.beat, "Strings 8", "/ finds the clip")
  keys("n")
  eq(paw.cursor.beat, 24, "n the next")
  keys("N")
  eq(paw.cursor.beat, 8, "N the one before")
  keys("gg0")
  keys("<Space>ft")
  keys("str<CR>")
  eq(cursor_track(), "Strings", "Space ft a track")
  keys("gg0")
  keys("<Space>fc")
  keys("verse 2<CR>")
  eq(cursor_track() .. " " .. paw.cursor.beat, "Strings 24", "Space fc a clip")
  keys("0")
  keys("<Space>fm")
  keys("outro<CR>")
  eq(paw.cursor.beat, 32, "Space fm a marker")
  keys("0")
  keys("]'")
  eq(paw.cursor.beat, 16, "]' the next marker")
  keys("]'")
  keys("['")
  eq(paw.cursor.beat, 16, "[' the one before")
  keys('g"')
  keys("<CR>")
  eq(paw.cursor.beat, 16, 'g" the list of markers')
  keys(":marker.goto Outro<CR>")
  eq(paw.cursor.beat, 32, ":marker.goto by name")
  keys(":marker.goto 1<CR>")
  eq(paw.cursor.beat, 16, "and by number")
  paw.cursor.set_beat(4)
  keys("g'")
  keys("Intro<CR>")
  eq(paw.markers.find("Intro").beat, 4, "g' asks for the name")
  paw.cursor.set_beat(8)
  keys("g'")
  keys("<CR>")
  eq(paw.markers.find("Marker 4") ~= nil and paw.markers.find("Marker 4").beat, 8, "no name typed: Marker 4")
  keys(":marker.rename Verse<CR>")
  eq(paw.markers.find("Verse").beat, 8, ":marker.rename names it again")
end)

test("guide: search the project and go through the results", function()
  start()
  local s = paw.add_track({ name = "Violins" })
  local v = paw.add_track({ name = "Violas" })
  local voice = paw.add_track({ name = "Voice" })
  s:add_clip({ name = "pizz", start = 0, length = 4, notes = { { pitch = 84, start = 0, length = 1 } } })
  v:add_clip({ name = "pizz", start = 8, length = 4, notes = { { pitch = 60, start = 0, length = 1, velocity = 127 } } })
  voice:add_clip({
    name = "line",
    start = 0,
    length = 4,
    notes = { { pitch = 64, start = 0, length = 1, meta = { lyric = "la" } } },
  })
  paw.cursor.set_track(voice)
  paw.cursor.set_beat(12)
  api.undo_checkpoint()
  keys(":vimgrep /pizz/<CR>")
  eq(#paw.qf.current().entries, 2, "two places")
  eq(cursor_track() .. " " .. paw.cursor.beat, "Violins 0", "the cursor goes to the first")
  keys("]q")
  eq(cursor_track() .. " " .. paw.cursor.beat, "Violas 8", "]q the next")
  keys("[q")
  eq(cursor_track(), "Violins", "[q the one before")
  keys(":copen<CR>")
  keys("q")
  paw.ui.focus("arrange")
  keys(":vimgrep /la/ lyric<CR>")
  local found = {}
  for _, e in ipairs(paw.qf.current().entries) do
    found[#found + 1] = e.text
  end
  eq(table.concat(found, " | "), "lyric: la", "only the lyrics")
  keys("<Space>fn")
  shows("la", "the notes with their lyrics")
  keys("<Esc>")
  paw.ui.close()
  paw.ui.focus("arrange")
  keys(":query note[pitch>=c6]<CR>")
  eq(#paw.qf.current().entries, 1, "one note from C6 up")
  keys(":query clip:has(note[vel>120])<CR>")
  eq(#paw.qf.current().entries, 1, "one clip with a loud note")
  keys(":vimgrep /^Viol/ track<CR>")
  keys(":cdo track.mute<CR>")
  local function muted() return tostring(s.mute) .. " " .. tostring(v.mute) .. " " .. tostring(voice.mute) end
  eq(muted(), "true true false", ":cdo mutes each track")
  keys("u")
  eq(muted(), "false false false", "as one undo step")
  keys(":select clip[name~=pizz]<CR>")
  keys("d")
  eq(#api.clip_list(s.id) + #api.clip_list(v.id), 0, ":select, then d deletes what it chose")
end)

test("guide: change a sound at a point in the song", function()
  start()
  for _, id in ipairs(api.track_list()) do
    paw.lanes.open(id, false)
  end
  local t = T.tone("Guitar", 8, "A3")
  local amp = t:add_device("gain", { gain = -40 })
  paw.cursor.set_track(t)
  paw.cursor.set_beat(2)
  keys("<Space>al")
  keys("state<CR>")
  local id = paw.cursor.lane_id()
  eq(id and api.lane_get(id).target, "state", "the state lane's row, with the cursor on it")
  keys("0\\s")
  eq(table.concat(api.lane_get(id).states, " "), "A", "the first sound is the state A")
  amp:set("gain", 0)
  keys("4l\\s")
  eq(table.concat(api.lane_get(id).states, " "), "A B", "the second sound is B")
  local pts = api.lane_points(id)
  eq(#pts, 2, "two points")
  eq(pts[1][1] == 0 and pts[2][2] == 1, true, "A from the start, B from the cursor")
  local text = screen()
  eq(text:find("B", 1, true) ~= nil, true, "the row shows the states")
  keys("c")
  keys("A<CR>")
  eq(api.lane_points(id)[2][2], 0, "c gives the point another state")
  keys("u")
  local info = T.render({ tail = 0, bits = 16 })
  local seconds = pts[2][1] * 60 / paw.tempo.at(0)
  local quiet = T.channel_peaks(info, 0.1, seconds - 0.05)
  local loud = T.channel_peaks(info, seconds + 0.05, seconds + 0.5)
  eq(loud > quiet * 10, true, string.format("the rendered file changes at the point (%.4f, %.4f)", quiet, loud))
end)

test("guide: use articulations with a plugin instrument", function()
  start()
  load_bundled("articulations")
  local art = require("articulations")
  local bass = paw.add_track({ name = "Bass" })
  bass:add_device("synth")
  local clip = bass:add_clip({
    start = 0,
    length = 4,
    notes = { { pitch = 40, start = 0, length = 1 }, { pitch = 43, start = 1, length = 1 } },
  })
  paw.flush()
  api.undo_checkpoint()
  -- The plugin as device_get tells it: the suite has no MODO BASS 2.
  local map = require("articulations.commands").auto_map(
    bass.id,
    { name = "MODO BASS 2", plugin = { format = "vst3", id = "0", name = "MODO BASS 2" } }
  )
  eq(map and art.info(bass.id).map, "plugins/ik-multimedia/modo-bass-2", "the map of the plugin binds itself")
  eq(paw.ui.messages[#paw.ui.messages].text:find("bound", 1, true) ~= nil, true, "a message tells so")

  -- Give notes an articulation.
  local roll = paw.ui.views.pianoroll
  roll:edit(clip)
  roll:set(40, 0)
  paw.ui.focus("pianoroll")
  keys("\\a")
  keys("slap<CR>")
  eq(art.m2.code(art.attr_of(clip:notes()[1])), "17.C", "the note is slapped")

  -- Move the keyswitches.
  paw.cursor.set_track(bass)
  keys(":art.shift -1oct<CR>")
  eq(art.attr_map(bass.id).arts["17.C"].out, "ks=D-1", "the keyswitch an octave down")
  keys(":art.shift 0<CR>")
  eq(art.attr_map(bass.id).arts["17.C"].out, "ks=D0", "and back")

  -- Bind a map by name.
  keys(":art.map sine-cc<CR>")
  eq(art.info(bass.id).map, "plugins/orchestral-tools/sine-cc", ":art.map binds a map by its name")

  -- A map of your own.
  keys(":art.new My bass<CR>")
  local file = api.env().config_dir .. "/articulations/my-bass.art.toml"
  eq(T.read_file(file) ~= nil, true, "an empty map to write in")

  -- The drums of a drum plugin.
  load_bundled("drums")
  local kit = paw.add_track({ name = "Kit" })
  paw.cursor.set_track(kit)
  keys(":drums.map mt-powerdrumkit<CR>")
  eq(require("drums").info(kit).map, "mt-powerdrumkit", "the notes of the kit have names")
end)

test("guide: write an importer or exporter", function()
  start()
  local dir = T.scratch .. "/howto-formats"
  api.fs_mkdir(dir)
  T.write_file(dir .. "/song.notes", "60 0 1\n64 1 1\n67 2 2\n")
  -- The guide's code, as it is on the page.
  local page = T.read_file("docs/how-to/write-an-importer-or-exporter.md")
  local code = page:match("```lua\n(paw%.formats%.register.-)```")
  assert(loadstring(code))()
  T.after(function() paw.formats.unregister("notes") end)
  keys(":import " .. dir .. "/song.notes<CR>")
  eq(#paw.tracks(), 1, ":import adds a track")
  eq(#paw.tracks()[1]:clips()[1]:notes(), 3, "with the notes of the file")
  keys(":export " .. dir .. "/copy.notes<CR>")
  eq(T.read_file(dir .. "/copy.notes"), "60 0 1\n64 1 1\n67 2 2\n", ":export writes them")
  local names = {}
  for _, c in ipairs(paw.commands.complete("import " .. dir .. "/so")) do
    names[#names + 1] = c.text
  end
  eq(table.concat(names, " "):find("song.notes", 1, true) ~= nil, true, ":import completes the files of the format")
  keys(":help formats<CR>")
  shows("help://formats.md", ":help formats opens the page of the formats")
  local _, _, text = paw.textbuf.here()
  local listed = false
  for row = 0, 40 do
    listed = listed or (text:line(row) or ""):find("Lists of notes", 1, true) ~= nil
  end
  eq(listed, true, "which lists it")
  keys(":q<CR>")
  keys(':lua paw.formats.unregister("notes")<CR>')
  eq(paw.formats.get("notes"), nil, "and it goes")
end)

test("guide: write an extension in Teal", function()
  start()
  local dir = T.scratch .. "/howto-teal"
  api.fs_mkdir(dir)
  -- The guide's extension, as it is on the page.
  local page = T.read_file("docs/how-to/write-an-extension-in-teal.md")
  local code = page:match('```lua\n   (paw.command%("scale.notes".-)   ```'):gsub("\n   ", "\n")
  T.write_file(dir .. "/scale.tl", code)
  eq(#paw.lang.check({ dir .. "/scale.tl" }), 0, "its types are correct")
  -- The examples of events and setters are correct Teal too.
  local events = page:match("```lua\n(local kernel = .-)```")
    .. page:match("```lua\n(local record Filled.-)```")
    .. "local id = 1\n"
    .. page:match("```lua\n(paw.api.track_set.-)```")
    .. page:match("```lua\n(local track: paw.Track.-)```")
    .. "print(volume)\n"
  T.write_file(dir .. "/events.tl", events)
  eq(#paw.lang.check({ dir .. "/events.tl" }), 0, "the examples of events, setters and objects check")
  -- The example of the library of Lua 5.3 checks, and its asserts hold.
  T.write_file(dir .. "/lib.tl", page:match("```lua\n(local function note_on.-)```"))
  eq(#paw.lang.check({ dir .. "/lib.tl" }), 0, "the example of the library checks")
  assert(paw.lang.loadfile(dir .. "/lib.tl"))()
  keys(':lua paw.ext.load("' .. dir .. '/scale.tl")<CR>')
  T.after(function() paw.ext.unload("scale") end)
  keys(":scale.notes C4 dorian<CR>")
  eq(paw.ui.message and paw.ui.message.text, "C4 D4 D#4 F4 G4 A4 A#4 C5", "the command says the notes")
end)

test("guide: configure an editor for paw's code", function()
  -- What the page says each server reads: the types of paw for both.
  local page = T.read_file("docs/how-to/configure-an-editor-for-paws-code.md")
  local include = table.concat(paw.lang.tlconfig().include_dir, " ")
  eq(include:find("runtime/types", 1, true) ~= nil, true, "tlconfig.lua points the Teal server at runtime/types")
  local luarc = T.read_file(".luarc.json")
  eq(
    luarc:find('"workspace.library": ["runtime/types"]', 1, true) ~= nil,
    true,
    ".luarc.json gives LuaLS runtime/types"
  )
  eq(luarc:find('"diagnostics.globals": ["paw"]', 1, true) ~= nil, true, "and the global paw")
  eq(T.read_file("runtime/types/paw.lua"):find("---@class paw\n", 1, true) ~= nil, true, "which declares paw")
  local example = page:match("for example\n   `([^`]+)`")
  eq(#paw.lang.check({ example }), 0, "the page's example file is there and checks")
end)

test("guide: write an extension in Teal, with the contracts and an option", function()
  start()
  local dir = T.scratch .. "/howto-teal-contracts"
  api.fs_mkdir(dir)
  -- The guide's option, view and picker, as they are on the page.
  local page = T.read_file("docs/how-to/write-an-extension-in-teal.md")
  local option = page:match("```lua\n(local steps = .-)```")
  local view = page:match("```lua\n   (local record Tally.-)   ```"):gsub("\n   ", "\n")
  local picker = page:match("```lua\n   (local record Fruit.-)   ```"):gsub("\n   ", "\n")
  local file = dir .. "/tally.tl"
  T.write_file(file, option .. view .. picker)
  eq(#paw.lang.check({ file }), 0, "its types are correct")
  keys(':lua paw.ext.load("' .. file .. '")<CR>')
  T.after(function() paw.ext.unload("tally") end)
  eq(paw.opt.euclid_steps, 32, "the option's handle set it")
  keys(":e tally<CR>")
  eq(paw.ui.focused, "tally", "the view shows")
  eq(paw.pick.sources.fruit.desc, "Fruit", "the picker is a source")
  -- A field with a wrong name is an error.
  T.write_file(file, option .. view:gsub('title = "Tally"', 'title = "Tally", on_keys = 1') .. picker)
  local found = paw.lang.check({ file })
  eq(found[1] and found[1].msg:find("unknown field on_keys", 1, true) ~= nil, true, "the misspelled field")
end)

test("guide: personalize the track column and the ruler", function()
  fresh()
  local fold, number = paw.trackcolumn.components.fold, paw.trackcolumn.components.number
  T.after(function()
    paw.trackcolumn.add("fold", fold)
    paw.trackcolumn.add("number", number)
    paw.trackcolumn.sign("armed", nil)
    paw.ruler.remove("eight")
    paw.opt.trackcolumn = { "number", "signs", "fold" }
    paw.opt.track_height = "auto"
  end)
  paw.opt.track_height = 1
  local drums = paw.add_track({ name = "Drums" })
  local bass = paw.add_track({ name = "Bass" })
  paw.groups.make({ drums, bass }, "Band")
  -- The code of the guide, as it gives it.
  paw.trackcolumn.set("fold", { order = 5, glyphs = { open = "-", closed = "+" } })
  paw.trackcolumn.set("number", { styles = { cursor = "Title" } })
  paw.trackcolumn.sign("armed", {
    priority = 20,
    render = function(track)
      if paw.track(track).armed then return { { "●", "Armed" } } end
    end,
    describe = function(track)
      if paw.track(track).armed then return "ready to record" end
    end,
  })
  paw.ruler.add("eight", {
    order = 5,
    render = function(bar)
      if bar > 1 and bar % 8 == 1 then return { { "·", "RulerTempo" } } end
    end,
  })
  bass.armed = true
  paw.cursor.set_track(bass)
  paw.flush()
  local text = screen(160, 30)
  eq(text:find("\n%- +1 ") ~= nil, true, "the folds at the far left, with a minus sign:\n" .. text)
  eq(text:find("3 ●", 1, true) ~= nil, true, "the armed track has its sign:\n" .. text)
  eq(text:find("·9", 1, true) ~= nil and text:find("·8", 1, true) == nil, true, "a dot before bar 9:\n" .. text)
  paw.keymap.feed("K")
  local described = screen(160, 30)
  while paw.ui.float do
    paw.ui.close()
  end
  eq(described:find("ready to record", 1, true) ~= nil, true, "K tells it:\n" .. described)
  keys(":set trackcolumn-=signs<CR>:set barlabel-=eight<CR>")
  text = table.concat(api.ui_snapshot(160, 30), "\n", 1, 4)
  eq(text:find("●", 1, true) == nil and text:find("·9", 1, true) == nil, true, ":set -= hides them:\n" .. text)
end)

test("guide: personalize insert mode", function()
  fresh()
  local r, m, f = paw.insert.get("r"), paw.insert.get("m"), paw.insert.get("f")
  local shown = paw.opt.insertkeys
  T.after(function()
    paw.keymap.feed("<Esc>")
    paw.insert.remove("M")
    paw.insert.remove("n")
    paw.insert.add("r", r)
    paw.insert.add("m", m)
    paw.insert.add("f", f)
    paw.opt.insertkeys = shown
  end)
  paw.ui.focus("arrange")
  local drums = paw.add_track({ name = "Drums" })
  paw.cursor.set_track(drums)
  paw.cursor.set_beat(0)
  paw.markers.add(12, "Chorus")
  api.undo_checkpoint()
  -- The code of the guide, as it gives it.
  paw.insert.set("r", { name = "Verse %d", length = "marker" })
  paw.insert.set("m", { length = "1 bar" })
  local notes = {}
  for beat = 0, 7 do
    notes[#notes + 1] = { pitch = 36, start = beat, length = 0.5 }
    if beat % 2 == 1 then notes[#notes + 1] = { pitch = 38, start = beat, length = 0.5 } end
  end
  paw.insert.add("M", {
    kind = "midi",
    desc = "A two-bar drum clip",
    length = "2 bars",
    name = "Drums %d",
    notes = notes,
  })
  keys("iMM<Esc>")
  local clips = drums:clips()
  table.sort(clips, function(a, b) return a.start < b.start end)
  eq(
    #clips .. " " .. clips[2].start .. " " .. clips[2].name .. " " .. #clips[2]:notes(),
    "2 8 Drums 2 12",
    "two drum clips, one after the other, with their notes"
  )
  keys("u")
  eq(#drums:clips(), 0, "u removes both")
  paw.cursor.set_beat(0)
  keys("ir<Esc>")
  local verse = paw.markers.region("Verse 1")
  eq(verse and verse.beat .. "+" .. verse.length, "0+12", "the region goes to the next marker")
  keys("im<Esc>")
  eq(drums:clips()[1].length, 4, "the MIDI clip is one bar long")
  paw.insert.set("m", { key = "n" })
  paw.insert.remove("f")
  local now = table.concat(paw.opt.insertkeys, ",")
  eq(now:find("n,a,r,'", 1, true) ~= nil and now:find("f", 1, true) == nil, true, "n in place of m, and no f: " .. now)
  paw.opt.insertkeys = { "n", "r", "'" }
  eq(#paw.insert.list(), 3, "only the keys of paw.opt.insertkeys work")
end)

test("guide: work on one section of a song", function()
  start()
  local keys_track = paw.add_track({ name = "Keys" })
  local strings = paw.add_track({ name = "Strings" })
  local bass = paw.add_track({ name = "Bass" })
  keys_track:add_clip({ name = "a", start = 0, length = 64 })
  strings:add_clip({ name = "b", start = 0, length = 64 })
  bass:add_clip({ name = "c", start = 0, length = 64 })
  paw.groups.make({ strings }, "Orchestra")
  paw.cursor.set_track(keys_track)
  paw.cursor.set_beat(16)
  api.undo_checkpoint()
  local tr = paw.transport
  keys("v15l<Space>rn")
  keys("Bridge<CR>")
  local bridge = paw.markers.region("Bridge")
  eq(bridge ~= nil, true, "<Space>rn made the region")
  keys(":narrow Bridge<CR>")
  eq(#paw.ui.tabs, 1, "in the same window")
  shows("Song › Bridge", "the status line shows the path")
  eq(
    paw.cursor.beat >= bridge.beat and paw.cursor.beat <= bridge.beat + bridge.length,
    true,
    "the cursor is in the section"
  )
  keys("0")
  eq(paw.cursor.beat, bridge.beat, "0 goes to its start")
  keys("3|")
  eq(
    paw.cursor.beat,
    bridge.beat + 8,
    "3| is bar 3 of the section (region " .. bridge.beat .. "+" .. bridge.length .. ")"
  )
  eq(tr.loop_enabled and tr.loop_start == bridge.beat, true, "the loop is the section")
  keys(":narrow Orchestra<CR>")
  shows("Song › Bridge › Orchestra", "narrow again: the path has both")
  keys("zw")
  shows("Song › Bridge", "zw goes up one level")
  keys(":set scopebars=song<CR>")
  eq(paw.opt.scopebars, "song", ":set scopebars=song")
  keys(":set noscopeloop<CR>")
  eq(paw.opt.scopeloop, false, ":set noscopeloop")
  keys(":widen!<CR>")
  eq(paw.scope.current(), nil, "the whole song")
  paw.opt.scopebars, paw.opt.scopeloop = "both", true
end)

test("guide: select a chord, a phrase, a voice or a pitch in the piano roll", function()
  start()
  local function N(pitch, s, length) return { pitch = pitch, start = s, length = length, velocity = 100 } end
  local t = paw.add_track({ name = "P" })
  t:add_device("synth")
  local c = t:add_clip({
    name = "a",
    start = 0,
    length = 8,
    notes = {
      N(48, 0, 2),
      N(52, 0, 2),
      N(55, 0, 2),
      N(72, 0, 1),
      N(74, 1, 1),
      N(50, 2, 2),
      N(53, 2, 2),
      N(57, 2, 2),
      N(76, 2, 2),
      N(60, 5, 0.5),
      N(64, 5.5, 0.5),
      N(67, 6, 0.5),
      N(72, 6.5, 0.5),
    },
  })
  paw.cursor.set_track(t)
  paw.cursor.set_beat(0)
  api.undo_checkpoint()
  keys("<CR>")
  eq(paw.ui.focused, "pianoroll", "Enter opens the piano roll")
  local roll = paw.ui.views.pianoroll
  local function yanked() return #paw.keymap.getreg().notes end
  roll:set(52, 0)
  keys("yic")
  eq(yanked(), 4, "yic: the notes that start with the note")
  keys("dic")
  eq(#c:notes(), 9, "dic deletes them")
  keys("u")
  roll:set(60, 5)
  keys("yac")
  eq(yanked(), 4, "yac: the broken chord")
  roll:set(52, 0)
  keys("vicicy")
  eq(yanked(), 8, "vic then ic takes in the next chord")
  roll:set(74, 1)
  waited("]c")
  eq(roll.pitch .. "@" .. roll.beat, "50@2", "]c goes to the next chord")
  keys("[c")
  eq(roll.pitch .. "@" .. roll.beat, "48@0", "[c goes back")
  roll:set(60, 5)
  keys("yip")
  eq(yanked(), 4, "yip: the phrase")
  keys(">ip")
  eq(notes(c):find("60@5.25", 1, true) ~= nil, true, ">ip moves the phrase later: " .. notes(c))
  keys("u")
  roll:set(60, 4.5)
  keys("yap")
  eq(yanked(), 4, "yap from a rest: the next phrase")
  roll:set(60, 0)
  keys(")")
  eq(roll.pitch .. "@" .. roll.beat, "60@5", ") goes to the next phrase")
  roll:set(67, 6)
  keys("(")
  eq(roll.beat, 5, "( goes to the start of this phrase")
  keys(":set phrase_rest=1.5<CR>")
  eq(paw.opt.phrase_rest, 1.5, ":set phrase_rest")
  paw.opt.phrase_rest = 0.5
  roll:set(52, 0)
  keys("yiv")
  eq(yanked(), 2, "yiv: the second line")
  roll:set(48, 0)
  keys("div")
  eq(notes(c):find("48@", 1, true), nil, "div deletes the bass line")
  eq(notes(c):find("52@0", 1, true) ~= nil, true, "and leaves the other notes")
  keys("u")
  roll:set(72, 0)
  keys("vi=+")
  eq(
    notes(c):find("73@0", 1, true) ~= nil and notes(c):find("72@", 1, true) == nil,
    true,
    "vi= then + moves every note of the pitch up"
  )
  keys("u")
  keys("va=")
  keys("<Esc>")
  keys("<C-w>p")
end)

test("guide: insert clips, regions and markers with keys", function()
  start()
  local t = paw.add_track({ name = "Keys" })
  paw.cursor.set_track(t)
  paw.cursor.set_beat(0)
  api.undo_checkpoint()
  keys("i")
  eq(paw.keymap.mode, "i", "i starts insert mode")
  shows("INSERT", "the status line shows INSERT")
  keys("m")
  eq(#t:clips(), 1, "m inserts a MIDI clip")
  eq(paw.cursor.beat, t:clips()[1].length, "the cursor moves to its end")
  keys("3m")
  eq(#t:clips(), 4, "3m inserts three more")
  keys("<BS>")
  eq(#t:clips(), 3, "Backspace removes the last item")
  keys("<Esc>")
  keys("u")
  eq(#t:clips(), 0, "u removes all the clips that one insert mode inserted")
  paw.cursor.set_beat(0)
  local before = #paw.markers.list()
  keys("ir")
  eq(#paw.markers.list(), before + 1, "r inserts a region")
  keys("'<Esc>")
  eq(#paw.markers.list(), before + 2, "' inserts a marker")
  keys("i")
  keys("<CR>")
  eq(paw.ui.focused, "pianoroll", "i then Enter opens a clip in the piano roll")
  keys("<C-w>p")
end)

test("guide: enter notes from a MIDI keyboard", function()
  start()
  local t = paw.add_track({ name = "Lead" })
  t:add_device("synth")
  local clip = t:add_clip({ name = "tune", start = 0, length = 4 })
  api.undo_checkpoint()
  paw.cursor.set_track(t)
  paw.cursor.set_beat(0)
  paw.opt.note_grid, paw.opt.velocity = 0.25, 100
  keys(":track.midi Keystation<CR>")
  keys("<CR>")
  eq(paw.ui.focused, "pianoroll", "Enter opens the clip in the piano roll")
  paw.ui.views.pianoroll:set(60, 0)
  keys("I")
  eq(paw.roll_draw.stepping(), true, "I starts step input")
  eq(paw.roll_draw.label():match("^STEP"), "STEP", "the title says STEP")
  keys("=8")
  local port = "Keystation 49"
  local function down(p) paw.midi.inject({ type = "note_on", pitch = p, velocity = 100, port = port }) end
  local function up(p) paw.midi.inject({ type = "note_off", pitch = p, port = port }) end
  local function play(p)
    down(p)
    up(p)
    paw.flush()
  end
  local function pedal(on)
    paw.midi.inject({ type = "cc", number = 64, value = on and 1 or 0, port = port })
    paw.flush()
  end
  play(60)
  down(64)
  down(67)
  up(64)
  up(67)
  paw.flush()
  keys("<Space>")
  play(72)
  keys("<BS>")
  play(74)
  pedal(true)
  pedal(false)
  keys("<Esc>")
  eq(T.melody(clip), "60@0+0.5 64@0.5+0.5 67@0.5+0.5 74@1+0.5", "a note, a chord, a rest, and the note after Backspace")
  keys("u")
  eq(#clip:notes(), 0, "u undoes all the notes at once")
  keys(":step.learn rest<CR>")
  down(36)
  paw.flush()
  eq(paw.ui.message.text:find("now does rest in step input", 1, true) ~= nil, true, "the pad is learned")
  keys("i")
  keys("I")
  down(36)
  paw.flush()
  eq(paw.roll_draw.label():match("^STEP rest"), "STEP rest", "the pad rests")
  keys("<Esc>")
  paw.step.unbind({ port = port, note = 36 })
end)
