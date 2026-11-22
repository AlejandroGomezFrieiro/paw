-- Routes between tracks besides outputs and sends: side-chains, which a
-- device on one track takes from another (runtime/lua/paw/routes.lua).
local T = ...
local test, eq, near, fails, fresh, render = T.test, T.eq, T.near, T.fails, T.fresh, T.render
local api = paw.api

local function plugin_kind(format, pattern)
  for _, info in ipairs(paw.device_types()) do
    if info.format == format and info.name:find(pattern) then return info.kind end
  end
end

--- A pad holding one note for eight beats, and a kick hitting on beats 0,
--- 2, 4 and 6 for a quarter of a beat each, at 120 BPM: a beat is half a
--- second, so the kick sounds from 0 to 0.125 s, 1 to 1.125 s and so on.
local function pad_and_kick()
  fresh()
  paw.project.tempo = 120
  local pad = paw.add_track({ name = "Pad" })
  pad:add_device("synth", { attack = 0.001, release = 0.01, wave = 0 })
  pad:add_clip({ start = 0, length = 8, notes = { { pitch = "A3", start = 0, length = 8 } } })
  local kick = paw.add_track({ name = "Kick" })
  kick:add_device("synth", { attack = 0.0005, release = 0.005, wave = 1, gain = 6 })
  local hits = {}
  for beat = 0, 6, 2 do
    hits[#hits + 1] = { pitch = "A2", start = beat, length = 0.25, velocity = 127 }
  end
  kick:add_clip({ start = 0, length = 8, notes = hits })
  return pad, kick
end

--- The pad's level while the kick hits and between the hits, from a render
--- where the kick is muted: it keys from before its fader, so it is not
--- heard but still drives the side-chain.
local function levels()
  local info = render({ tail = 0, bits = 16 })
  local during = T.channel_peaks(info, 1.03, 1.11)
  local between = T.channel_peaks(info, 1.6, 1.9)
  return during, between
end

test("a compressor ducks a pad under a kick through its side-chain", function()
  local pad, kick = pad_and_kick()
  local comp = pad:add_device("compressor", { threshold = -10, ratio = 20, attack = 0.1, release = 20, knee = 0 })
  kick.mute = true
  local during, between = levels()
  eq(between > 0.05, true, "the pad sounds")
  near(during / between, 1, 0.1, "listening to its own quiet input the compressor leaves the pad alone")

  comp:set_sidechain(kick, { pre = true })
  comp:set({ threshold = -30, ratio = 50 })
  eq(comp.sidechain, kick.id, "the device names the track it listens to")
  eq(comp.sidechain_pre, true, "and that it takes it before the fader")
  during, between = levels()
  eq(during < between * 0.1, true, string.format("the pad ducks under the kick: %.3f against %.3f", during, between))

  comp:set("listen", 1)
  during, between = levels()
  eq(
    during > 0.05 and between < 0.002,
    true,
    string.format("listening plays the key alone: %.3f, then %.4f", during, between)
  )

  comp:set("listen", 0)
  comp.sidechain_pre = false
  during, between = levels()
  near(during / between, 1, 0.1, "after the fader, a muted kick keys nothing")
  kick.mute = false
  kick.volume = -120
  during, between = levels()
  near(during / between, 1, 0.1, "nor does one faded out")
end)

test("soloing the track a compressor ducks does not cut its key", function()
  local pad, kick = pad_and_kick()
  local comp = pad:add_device("compressor", { threshold = -30, ratio = 50, attack = 0.1, release = 20, knee = 0 })
  comp:set_sidechain(kick)
  pad.solo = true
  local during, between = levels()
  eq(between > 0.05, true, "the soloed pad sounds")
  eq(
    during < between * 0.1,
    true,
    string.format("and still ducks under the kick it does not hear: %.3f against %.3f", during, between)
  )
  pad.solo = false
  kick.mute = true
  during, between = levels()
  near(during / between, 1, 0.1, "while muting the kick still cuts a key taken after its fader")
end)

test("a gate opens for the key, not for what it gates", function()
  local pad, kick = pad_and_kick()
  local gate = pad:add_device("gate", { threshold = -30, range = -80, attack = 0.1, hold = 0, release = 10 })
  kick.mute = true
  gate:set_sidechain(kick, { pre = true })
  local during, between = levels()
  eq(
    during > 0.05 and between < 0.002,
    true,
    string.format("open on the kick, shut between: %.3f, %.4f", during, between)
  )
end)

test("a side-chain lines up with what the device hears, through latency on either side", function()
  fresh()
  paw.project.tempo = 120
  -- The pad's track plays the kick upside down, through a gate that
  -- listens to the kick: if the two meet at the master at the same time
  -- they cancel. The kick is late through a look-ahead limiter, and the
  -- devices before the gate are late through a compressor's look-ahead.
  local pad = paw.add_track({ name = "Pad" })
  pad:add_device("compressor", { lookahead = 3, threshold = 0 })
  local gate = pad:add_device("gate", { listen = 1 })
  pad:add_device("utility", { invert_l = 1, invert_r = 1 })
  local kick = paw.add_track({ name = "Kick" })
  kick:add_device("synth", { attack = 0.0005, release = 0.005, wave = 1 })
  kick:add_device("limiter", { ceiling = -3 })
  kick:add_clip({ start = 0, length = 4, notes = { { pitch = "A2", start = 1, length = 0.5 } } })
  gate:set_sidechain(kick)
  local info = render({ tail = 0.2, bits = 16 })
  eq(T.channel_peaks(info, 0, 2.2) < 1e-4, true, "the kick and its upside-down key cancel")
  gate.sidechain = nil
  info = render({ tail = 0.2, bits = 16 })
  eq(T.channel_peaks(info, 0.5, 1) > 0.05, true, "without the key the kick is heard")
end)

test("side-chains, output pairs and the threads that process tracks: the same file, byte for byte", function()
  fresh()
  local bus = paw.add_track({ name = "bus" })
  bus:add_device("compressor", { threshold = -30, ratio = 8, attack = 1, release = 40, lookahead = 2 })
  local keys = {}
  for i = 1, 12 do
    local t = paw.add_track({ name = "voice " .. i, pan = (i - 6) / 8 })
    t:add_device("synth", { wave = i % 4, attack = 0.002, release = 0.05 })
    if i % 3 == 0 then t:add_device("limiter") end
    local notes = {}
    for step = 0, 15 do
      notes[#notes + 1] = { pitch = 36 + (i * 7 + step * 5) % 36, start = step * 0.5, length = 0.3 }
    end
    t:add_clip({ start = 0, length = 8, notes = notes })
    if i % 2 == 0 then t.output = bus end
    if i % 4 == 1 then t:send(bus, -6, { pre = true }) end
    keys[i] = t
  end
  -- Each odd voice ducks under the next one up, and the bus under voice 3.
  for i = 1, 11, 2 do
    local comp = keys[i]:add_device("compressor", { threshold = -30, ratio = 6, attack = 0.5, release = 30 })
    comp:set_sidechain(keys[i + 1], { pre = i % 4 == 1 })
  end
  bus:devices()[1]:set_sidechain(keys[3])
  -- And a kit whose kick plays into the bus and whose hats into a voice.
  local drums = paw.add_track({ name = "kit" })
  local kit = drums:add_device("drums")
  drums:add_device("limiter")
  local beats = {}
  for step = 0, 15 do
    beats[#beats + 1] = { pitch = ({ 36, 42, 38, 42 })[step % 4 + 1], start = step * 0.5, length = 0.25 }
  end
  drums:add_clip({ start = 0, length = 8, notes = beats })
  kit:set_output(2, bus)
  kit:set_output(4, keys[5])
  paw.flush()
  local alone = render({ tail = 0.5, threads = 1 })
  eq(alone.peak > 0.05, true, "something sounds")
  local want = T.read_file(alone.path)
  for _, threads in ipairs({ 2, 5, 16 }) do
    local info = render({ tail = 0.5, threads = threads })
    eq(T.read_file(info.path) == want, true, "on " .. threads .. " threads the same file")
  end
end)

test("a side-chain that would make a loop is refused, in every combination with outputs and sends", function()
  fresh()
  local a, b, c = paw.add_track({ name = "A" }), paw.add_track({ name = "B" }), paw.add_track({ name = "C" })
  local on_a = a:add_device("compressor")
  local on_b = b:add_device("compressor")
  local on_c = c:add_device("gate")
  fails(function() on_a:set_sidechain(a) end, "its own track", "a device on its own track")
  fails(function() on_a.sidechain = 0 end, "master", "the master")
  fails(function() on_a.sidechain = 999 end, "no track", "a track that is not there")

  a.output = b
  fails(function() on_a:set_sidechain(b) end, "loop", "from the track its own plays into")
  a.output = nil
  a:send(b, -6)
  fails(function() on_a:set_sidechain(b) end, "loop", "from the track its own sends to")
  paw.frontend.act.remove_send(a.id, 1)

  on_b:set_sidechain(a)
  fails(function() b.output = a end, "loop", "an output into the track it listens to")
  fails(function() b:send(a, 0) end, "loop", "a send into the track it listens to")
  fails(function() on_a:set_sidechain(b) end, "loop", "listening back the other way")
  on_c:set_sidechain(b)
  fails(function() on_a:set_sidechain(c) end, "loop", "round three tracks")
  fails(function() c.output = a end, "loop", "an output round three tracks")
  fails(function() api.device_move(on_b.id, a.id, 1) end, "loop", "moving the device onto the track it listens to")
  eq(on_b:track().id, b.id, "which stays where it was")

  -- What the frontends offer leaves out what would be refused.
  local names = {}
  for _, source in ipairs(paw.routes.sidechain_sources(on_a.id)) do
    names[#names + 1] = source.name
  end
  eq(table.concat(names, " "), "", "A can listen to nothing: B and C both hear it")
  names = {}
  for _, target in ipairs(paw.frontend.routing(a.id).targets) do
    names[#names + 1] = target.name
  end
  eq(table.concat(names, " "), "Master B C", "but it can play into them")
  names = {}
  for _, source in ipairs(paw.routes.sidechain_sources(on_c.id)) do
    names[#names + 1] = source.name
  end
  eq(table.concat(names, " "), "A B", "C can listen to the others")
end)

test("removing the track a device listens to takes the side-chain away, and undo brings it back", function()
  fresh()
  local pad, kick = paw.add_track({ name = "Pad" }), paw.add_track({ name = "Kick" })
  local comp = pad:add_device("compressor")
  local on_master = paw.master:add_device("compressor")
  comp:set_sidechain(kick, { pre = true })
  on_master:set_sidechain(kick)
  eq(api.track_get(pad.id).listens[1], kick.id, "the track says what it listens to")
  api.undo_checkpoint()
  kick:remove()
  eq(comp.sidechain, nil, "the device listens to its own input again")
  eq(comp.sidechain_pre, false, "and forgets where it took it")
  eq(on_master.sidechain, nil, "so does one on the master")
  paw.undo()
  eq(comp.sidechain, kick.id, "undo puts the side-chain back")
  eq(comp.sidechain_pre, true, "as it was")
end)

test("side-chains are saved, loaded, copied with a track, and left out of templates", function()
  fresh()
  local pad, kick = paw.add_track({ name = "Pad" }), paw.add_track({ name = "Kick" })
  local comp = pad:add_device("compressor")
  pad:add_device("delay")
  comp:set_sidechain(kick, { pre = true })
  local path = T.scratch .. "/sidechain.json"
  paw.project.save(path)
  local text = T.read_file(path)
  -- The project is named after its file: count the field, not the name.
  eq(select(2, text:gsub('"sidechain":', "")), 1, "the one side-chain is written")
  paw.project.load(path)
  local loaded = paw.track("Pad"):devices()[1]
  eq(loaded.sidechain, paw.track("Kick").id, "and read back")
  eq(loaded.sidechain_pre, true, "with where it is taken")

  local copy = paw.track("Pad"):duplicate()
  eq(copy:devices()[1].sidechain, paw.track("Kick").id, "a copy of the track listens to the same track")
  local snap = paw.track("Pad"):snapshot()
  paw.track("Kick"):remove()
  local restored = paw.restore_track(snap)
  eq(restored:devices()[1].sidechain, nil, "a track restored after its key is gone listens to its own input")

  fresh()
  local plain = paw.add_track({ name = "Plain" })
  plain:add_device("compressor")
  paw.project.save(path)
  eq(T.read_file(path):find('"sidechain":', 1, true), nil, "a project without side-chains is written as before")
end)

test("the device panel and the window choose a device's side-chain", function()
  fresh()
  local pad, kick = paw.add_track({ name = "Pad" }), paw.add_track({ name = "Kick" })
  local _ = paw.add_track({ name = "Hats" })
  local comp = pad:add_device("compressor")
  pad:add_device("delay")
  paw.cursor.set_track(pad)
  paw.ui.focus("devices")
  paw.ui.views.devices.row = 1
  paw.commands.exec("device.sidechain Kick pre=1")
  eq(comp.sidechain .. " " .. tostring(comp.sidechain_pre), kick.id .. " true", ":device.sidechain sets it")
  paw.flush()
  local text = table.concat(api.ui_snapshot(140, 30), "\n")
  eq(text:find("key Kick pre", 1, true) ~= nil, true, "the device panel shows it:\n" .. text)
  paw.commands.exec("device.sidechain none")
  eq(comp.sidechain, nil, ":device.sidechain none takes it away")
  paw.keymap.feed("K")
  eq(paw.ui.float ~= nil, true, "K chooses from a list")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")

  local state = paw.frontend.state(-1)
  local card = state.devices[1]
  eq(card.keyed, true, "the window knows the compressor can listen to a side-chain")
  eq(state.devices[2].keyed, false, "and the delay cannot")
  eq(card.sidechain, "", "it listens to nothing yet")
  local menu = paw.frontend.sidechain_menu(comp.id)
  local labels = {}
  for i, entry in ipairs(menu) do
    labels[i] = entry.label
  end
  eq(
    table.concat(labels, "|"),
    "None: its own input|Kick|Hats|Before the fader",
    "its menu lists the tracks it can hear"
  )
  paw.frontend.act.choose_sidechain(comp.id, 3)
  eq(comp.sidechain, paw.track("Hats").id, "choosing one sets it")
  paw.frontend.act.choose_sidechain(comp.id, 4)
  eq(comp.sidechain_pre, true, "the last entry takes it before the fader")
  eq(paw.frontend.state(-1).devices[1].sidechain, "Hats pre", "which the card shows")
  eq(paw.frontend.sidechain_menu(comp.id)[3].checked, true, "and the menu ticks")
  paw.frontend.act.choose_sidechain(comp.id, 1)
  eq(comp.sidechain, nil, "None takes it away")
end)

-- Plugins with a side-chain input, in each format.
for _, format in ipairs({ "clap", "lv2", "vst3" }) do
  test(format .. " side-chain plugins hear the key", function()
    local kind = plugin_kind(format, "Sidechain Compressor Stereo$")
    if not kind then return "skipped: test plugins not found" end
    local pad, kick = pad_and_kick()
    local comp = pad:add_device(kind)
    eq(comp.ports.sidechain, true, "the plugin says it takes a side-chain")
    comp:set("Sidechain listen", 1)
    kick.mute = true
    comp:set_sidechain(kick, { pre = true })
    local during, between = levels()
    eq(
      during > 0.02 and between < 0.01,
      true,
      string.format("listening, it plays the kick: %.3f, then %.4f", during, between)
    )
    comp.sidechain = nil
    during = levels()
    eq(during < 0.01, true, string.format("without a key it hears nothing: %.4f", during))
  end)
end

-- Devices with more than one output pair -----------------------------------------

--- A kit on its own track with a kick on beat 0 and a snare on beat 2, at
--- 120 BPM: the kick sounds from 0 s, the snare from 1 s.
local function kit_and_kick()
  fresh()
  paw.project.tempo = 120
  local drums = paw.add_track({ name = "Drums" })
  local kit = drums:add_device("drums")
  drums:add_clip({
    start = 0,
    length = 4,
    notes = { { pitch = 36, start = 0, length = 0.5 }, { pitch = 38, start = 2, length = 0.5 } },
  })
  local kick = paw.add_track({ name = "Kick" })
  return drums, kit, kick
end

--- Peaks while the kick sounds and while the snare does.
local function kick_and_snare()
  local info = render({ tail = 0, bits = 16 })
  return T.channel_peaks(info, 0.01, 0.2), T.channel_peaks(info, 1.01, 1.2)
end

test("a kit's routed pair plays on the track it is routed to, and leaves the kit's own", function()
  local drums, kit, kick = kit_and_kick()
  eq(table.concat(kit.ports.outputs, " "), "Kit Kick Snare Hats Toms Cymbals Percussion", "the kit names its pairs")
  kit:set_output(2, kick)
  eq(kit.outputs["2"], kick.id, "the device says where its second pair plays")
  drums.volume = -120
  local k, s = kick_and_snare()
  eq(
    k > 0.05 and s < 0.001,
    true,
    string.format("the kick plays through its own track, not the kit's fader: %.3f, %.4f", k, s)
  )
  drums.volume = 0
  kick.volume = -120
  k, s = kick_and_snare()
  eq(k < 0.001 and s > 0.05, true, string.format("and is no longer on the kit's pair: %.4f, %.3f", k, s))
  kit:set_output(2, nil)
  eq(next(kit.outputs), nil, "a pair taken away plays nowhere")
  k = kick_and_snare()
  eq(k > 0.05, true, "and the kit has its kick back")
end)

test("a pair routed elsewhere is lined up with the rest through latency on either side", function()
  fresh()
  paw.project.tempo = 120
  local notes = { { pitch = 36, start = 1, length = 0.5 } }
  -- One kit plays the kick on its own track through a look-ahead; another
  -- plays it on its kick pair, which leaves before a longer look-ahead and
  -- is turned upside down on the track it plays into: they cancel.
  local a = paw.add_track({ name = "A" })
  a:add_device("drums")
  a:add_device("compressor", { lookahead = 3, ratio = 1 })
  a:add_clip({ start = 0, length = 4, notes = notes })
  local b = paw.add_track({ name = "B" })
  local kit = b:add_device("drums")
  b:add_device("compressor", { lookahead = 5, ratio = 1 })
  b:add_clip({ start = 0, length = 4, notes = notes })
  local flip = paw.add_track({ name = "Flip" })
  flip:add_device("utility", { invert_l = 1, invert_r = 1 })
  kit:set_output(2, flip)
  local info = render({ tail = 0.2, bits = 16 })
  eq(T.channel_peaks(info, 0, 2.2) < 1e-4, true, "the two kicks cancel")
  kit:set_output(2, nil)
  info = render({ tail = 0.2, bits = 16 })
  eq(T.channel_peaks(info, 0.5, 1) > 0.05, true, "and without the pair they do not")
end)

test("output pairs that would make a loop are refused, with outputs, sends and side-chains", function()
  local drums, kit, kick = kit_and_kick()
  fails(function() kit:set_output(2, drums) end, "own track", "into the kit's own track")
  fails(function() kit:set_output(1, kick) end, "from 2", "the first pair, which plays on the kit's track")
  fails(function() kit:set_output(2, 999) end, "no track", "into a track that is not there")
  local on_master = paw.master:add_device("drums")
  fails(function() on_master:set_output(2, kick) end, "master", "from the master")
  kit:set_output(2, kick)
  fails(function() kick.output = drums end, "loop", "the kick track playing back into the kit's")
  fails(function() kick:send(drums, 0) end, "loop", "sending back")
  local comp = drums:add_device("compressor")
  fails(function() comp:set_sidechain(kick) end, "loop", "the kit's track listening to the kick track")
  local other = paw.add_track({ name = "Other" })
  other:add_device("compressor"):set_sidechain(kick)
  local second = other:add_device("drums")
  fails(function() second:set_output(2, drums) end, "loop", "round three tracks, through a side-chain")
  local names = {}
  for _, entry in ipairs(paw.frontend.outputs_menu(kit.id)[1].choices) do
    names[#names + 1] = entry.label
  end
  eq(table.concat(names, "|"), "Nowhere: not heard|Kick|Other", "the window offers the tracks it can play into")
end)

test("removing the track a pair plays into takes the route away, and undo brings it back", function()
  local _, kit, kick = kit_and_kick()
  kit:set_output(3, kick)
  api.undo_checkpoint()
  kick:remove()
  eq(next(kit.outputs), nil, "the pair plays nowhere")
  paw.undo()
  eq(kit.outputs["3"], kick.id, "undo routes it again")
end)

test("routed pairs are saved and loaded, left out of copies and templates", function()
  local _, kit, kick = kit_and_kick()
  kit:set_output(2, kick)
  local path = T.scratch .. "/pairs.json"
  paw.project.save(path)
  paw.project.load(path)
  local loaded = paw.track("Drums"):devices()[1]
  eq(loaded.outputs["2"], paw.track("Kick").id, "the pair is read back")
  local copy = paw.track("Drums"):duplicate()
  eq(next(copy:devices()[1].outputs), nil, "a copy of the track plays its pairs nowhere")
  local snap = paw.track("Drums"):snapshot()
  paw.track("Kick"):remove()
  local restored = paw.restore_track(snap)
  eq(next(restored:devices()[1].outputs), nil, "restored after the track is gone, the pair plays nowhere")
end)

test("spreading a kit's outputs makes a track for each pair, grouped with the kit's", function()
  local drums, kit = kit_and_kick()
  paw.track("Kick"):remove()
  local made = paw.routes.spread(kit.id)
  local names = {}
  for i, t in ipairs(made) do
    names[i] = t.name
  end
  eq(table.concat(names, " "), "Kick Snare Hats Toms Cymbals Percussion", "named after the pairs")
  eq(kit.outputs["2"], made[1].id, "each pair plays on its track")
  eq(kit.outputs["7"], made[6].id, "the last too")
  local group = paw.groups.of(drums)
  eq(group ~= nil and api.track_get(group).name, "Drums outputs", "the kit's track and the new ones are in a group")
  eq(paw.groups.of(made[3]), group, "all of them")
  eq(#paw.routes.spread(kit.id), 0, "spreading again makes nothing more")
  eq(kick_and_snare() > 0.05, true, "the kick sounds through its new track")
end)

test("the window and the device panel route a kit's pairs", function()
  local drums, kit, kick = kit_and_kick()
  paw.add_track({ name = "Snare" })
  paw.cursor.set_track(drums)
  local card = paw.frontend.state(-1).devices[1]
  eq(card.pairs .. " " .. card.routed, "7 0", "the card knows the kit has seven pairs, none routed")
  local menu = paw.frontend.outputs_menu(kit.id)
  eq(#menu, 6, "the menu has the six further pairs")
  eq(menu[1].label, "2 Kick → not heard", "each says where it plays")
  paw.frontend.act.route_pair(kit.id, 2, 2)
  eq(kit.outputs["2"], kick.id, "choosing a track routes the pair")
  eq(paw.frontend.outputs_menu(kit.id)[1].choices[2].checked, true, "which the menu ticks")
  paw.frontend.act.route_pair(kit.id, 2, 1)
  eq(next(kit.outputs), nil, "and Nowhere takes it away")

  paw.ui.focus("devices")
  paw.ui.views.devices.row = 1
  paw.commands.exec("device.output 3 Snare")
  eq(kit.outputs["3"], paw.track("Snare").id, ":device.output routes a pair by number")
  paw.flush()
  local text = table.concat(api.ui_snapshot(140, 30), "\n")
  eq(text:find("outs 1/6", 1, true) ~= nil, true, "the device panel counts the routed pairs")
  paw.commands.exec("device.output 3 none")
  eq(next(kit.outputs), nil, ":device.output 3 none takes it away")
  paw.commands.exec("device.spread")
  eq(kit.outputs["2"] ~= nil, true, ":device.spread spreads them")
  paw.ui.focus("arrange")
end)

-- Plugins with several output pairs, in each format.
for _, case in ipairs({
  { "clap", "^Surge XT$" },
  { "clap", "Multi%-Sampler x12 DirectOut" },
  { "lv2", "Multi%-Sampler x12 DirectOut" },
  { "vst3", "Multi%-Sampler x12 DirectOut" },
}) do
  local format, pattern = case[1], case[2]
  test(format .. " " .. pattern:gsub("[%^%$%%]", "") .. " names its output pairs, and one is routed", function()
    local kind = plugin_kind(format, pattern)
    if not kind then return "skipped: test plugins not found" end
    fresh()
    local inst = paw.add_track({ name = "Inst" })
    local d = inst:add_device(kind)
    local outputs = d.ports.outputs
    eq(#outputs > 1, true, "it has several pairs: " .. table.concat(outputs, ", "))
    local out = paw.add_track({ name = "Out" })
    d:set_output(2, out)
    eq(d.outputs["2"], out.id, "a pair is routed")
    local info = render({ tail = 0, bits = 16, start = 0, ["end"] = 2 })
    eq(info.frames > 0, true, "and the project renders with it")
  end)
end
