-- Tests of the virtual inputs; tests/suite.lua runs them. The tracker is
-- played by a script that prints what gdi2m prints.
local T = ...
local test, eq, near, fresh = T.test, T.eq, T.near, T.fresh
local api = paw.api

local fake = T.scratch .. "/fake-gdi2m"
local kept = T.scratch .. "/vinput/inputs.json"
local vinput, run, panel

--- A stand-in for gdi2m: lists ports, and "tracks" until it is asked to
--- finish, saying each fifth of a second what gdi2m says each second.
local function write_fake()
  local file = assert(io.open(fake, "w"))
  file:write([[#!/bin/sh
if [ "$2" = "--list" ]; then
  printf 'capture devices:\n  [0] (nothing - wire a source to gdi2m:in yourself)   (default)\n'
  printf '  [1] Steinberg UR22mkII  Input 2:capture_MONO\n  [2] Steinberg UR22mkII  Input 1:capture_MONO\n'
  printf '\nrender devices (--sine-device):\n  [0] Steinberg UR22mkII  Stereo Output   (default)\n'
  printf '\nmidi outputs:\n  [0] gdi2m:midi_out  (own port, nothing wired)\n'
  exit 0
fi
echo "$@" > "$0.args"
if [ "$3" = "Nowhere" ]; then echo "no capture port matching 'Nowhere'"; exit 1; fi
echo "gain      x$7"
echo "midi      [4] Midi-Bridge:$5, channel 1"
trap 'printf "\n-- session --\n  3.0 s wall, 560 frames (3.0 s of audio), 7 notes\n  hops pushed 566, dropped 0, peak queue depth 4 of 64\n  -> 1.8 dB LOW. Use --gain 1.23 to land on it, which would put the\n"; exit 0' TERM INT
n=0
while true; do
  n=$((n + 1))
  echo "  $n.0s  in -9.5 pk / -21.0 rms dBFS  [ch0 -9.5]  act -19.8 dBFS  q 2  notes $n (1.0/s)  inf 2.93 mean / 3.91 max ms"
  sleep 0.2
done
]])
  file:close()
  os.execute("chmod +x '" .. fake .. "'")
end

local function load()
  if not vinput then
    write_fake()
    paw.opt.vinput_file = kept
    paw.opt.vinput_gdi2m = fake
    paw.opt.vinput_run = false
    paw.ext.load("extensions/vinput")
    vinput, run, panel = require("vinput"), require("vinput.run"), require("vinput.panel")
    run.PERIOD, run.SETTLE, run.GRACE, run.RETRY = 40, 50, 1000, 60
  end
  local function remove_all()
    for i = #vinput.inputs, 1, -1 do
      vinput.remove(vinput.inputs[i].name)
    end
  end
  -- Each input has a MIDI port of the program's own: none stays after the test.
  remove_all()
  T.after(remove_all)
  -- The runner gives the options back after each test.
  paw.opt.vinput_file = kept
  paw.opt.vinput_run = false
  paw.opt.vinput_gdi2m = fake
  return vinput
end

--- Let time pass until `done()` or three seconds are over.
local function settle(done)
  local deadline = api.now() + 3000
  while api.now() < deadline and not done() do
    paw.wait(20)
  end
  return done()
end

local keys = T.keys

local function own_ports()
  local out = {}
  for _, port in ipairs(paw.midi.inputs()) do
    if port.own then out[#out + 1] = port.name end
  end
  return table.concat(out, ", ")
end

test("vinput: an input is a MIDI port of the program's own, with a chain of settings", function()
  fresh()
  load()
  local input = vinput.add({ name = "Guitar" })
  eq(
    input.kind .. " " .. input.gain .. " " .. input.threshold .. " " .. input.channel,
    "gdi2m 1 0.85 1",
    "a new input has the tracker's usual settings"
  )
  eq(own_ports(), "Guitar", "and a MIDI port by its name")
  eq(vinput.add({}).name, "Guitar 2", "a second one gets a name of its own")
  vinput.set("Guitar", "gain", 99)
  eq(input.gain, 8, "a number stays in its range")
  vinput.set("Guitar", "channel", "3.4")
  eq(input.channel, 3, "a channel is a whole number")
  vinput.set("Guitar", "attack_velocity", "on")
  eq(input.attack_velocity, true, "a switch reads on and off")
  T.fails(function() vinput.set("Guitar", "split", "soup") end, "pitch and a channel", "a split that is not one")
  T.fails(function() vinput.set("Guitar", "volume", 1) end, "no setting", "a setting there is not")
  vinput.set("Guitar", "split", "E3:2, 64:3")
  vinput.set("Guitar", "source", "Steinberg UR22mkII  Input 2:capture_MONO")
  local argv = table.concat(vinput.kinds.gdi2m.argv(input), "|")
  eq(
    argv:find("live|--device|Steinberg UR22mkII  Input 2:capture_MONO|--port|paw:Guitar (playback)|--gain|8|", 1, true)
      ~= nil,
    true,
    "the tracker is given the source and this program's port"
  )
  eq(argv:find("|--channel|3|--attack-velocity|--split|52:2,64:3", 1, true) ~= nil, true, "and how the notes go out")
  eq(vinput.remove("Guitar 2"), true, "an input is taken away")
  eq(own_ports(), "Guitar", "with its port")
end)

test("vinput: a track takes the input by name, and follows when it is renamed", function()
  fresh()
  load()
  vinput.add({ name = "Guitar" })
  local track = vinput.make_track("Guitar")
  eq(
    track.name .. " " .. track.midi_input.port .. " " .. tostring(track.armed),
    "Guitar Guitar true",
    "a track made for the input takes it, armed"
  )
  eq(#track:devices(), 1, "with an instrument to hear it through")
  local other = paw.add_track({ name = "Keys" })
  other:add_device("synth")
  other.midi_input = { port = "Keys A" }
  other.armed = true
  paw.flush()
  paw.midi.inject({ type = "note_on", pitch = 52, velocity = 100, port = "Guitar" })
  T.until_(
    function() return select(1, track:meter()) > 0.01 end,
    "what arrives at the input's port to be heard on its track"
  )
  eq(select(1, other:meter()), 0, "and not on a track that takes another port")
  paw.midi.inject({ type = "note_off", pitch = 52, port = "Guitar" })
  vinput.set("Guitar", "name", "Strat")
  eq(own_ports(), "Strat", "a renamed input has a port by the new name")
  eq(track.midi_input.port, "Strat", "and its track goes with it")
  eq(other.midi_input.port, "Keys A", "other tracks stay as they were")
  T.fails(function() vinput.set("Strat", "name", "") end, "needs a name", "an input with no name")
end)

test("vinput: the inputs are kept in a file and are there at the next start", function()
  fresh()
  load()
  vinput.add({ name = "Guitar", source = "Input 2", gain = 1.25, threshold = 0.8 })
  vinput.add({ name = "Bass", on = false })
  vinput.save()
  local file = assert(io.open(kept, "r"))
  local data = paw.json.decode(file:read("*a"))
  file:close()
  eq(#data.inputs .. " " .. data.inputs[1].name .. " " .. data.inputs[1].gain, "2 Guitar 1.25", "the file has them")
  -- As a new start would: nothing known, then the file is read.
  for _, input in ipairs(vinput.inputs) do
    paw.midi.close_port(input.name)
  end
  vinput.inputs = {}
  vinput.load()
  local guitar, bass = vinput.get("Guitar"), vinput.get("Bass")
  eq(
    guitar.source .. " " .. guitar.gain .. " " .. guitar.threshold .. " " .. tostring(guitar.on),
    "Input 2 1.25 0.8 true",
    "settings come back"
  )
  eq(tostring(bass.on) .. " " .. bass.mute_drop, "false 20", "an input that was off is off, with the rest as usual")
  eq(own_ports(), "Guitar, Bass", "and their ports are open again")
end)

test("vinput: the tracker runs while the input is on, and is started again when a setting changes", function()
  fresh()
  load()
  local input = vinput.add({ name = "Guitar" })
  eq(vinput.status("Guitar").text, "waits for an audio device", "without a real audio device nothing is run")
  paw.opt.vinput_run = true
  run.sync()
  eq(
    vinput.status("Guitar").state .. ": " .. vinput.status("Guitar").text,
    "blocked: not ready: choose the guitar's input",
    "an input with no source says so"
  )
  vinput.set("Guitar", "source", "Input 2")
  eq(settle(function() return vinput.status("Guitar").state == "running" end), true, "with a source the tracker runs")
  eq(
    settle(function() return (vinput.status("Guitar").notes or 0) >= 2 end),
    true,
    "and what it prints is read as it goes"
  )
  local status = vinput.status("Guitar")
  near(status.level, -19.8, 0.01, "the level it hears")
  near(status.peak, -9.5, 0.01, "the loudest the source was")
  near(status.load, 2.93, 0.01, "and how long a frame takes it")
  local file = assert(io.open(fake .. ".args", "r"))
  local args = file:read("*a")
  file:close()
  eq(
    args:find("--device Input 2 --port paw:Guitar (playback) --gain 1 ", 1, true) ~= nil,
    true,
    "it was started with the input's settings"
  )

  vinput.set("Guitar", "gain", 2)
  eq(
    settle(function()
      local f = io.open(fake .. ".args", "r")
      local now = f and f:read("*a") or ""
      if f then f:close() end
      return now:find("--gain 2 ", 1, true) ~= nil and vinput.status("Guitar").state == "running"
    end),
    true,
    "a changed setting starts it again with the new value"
  )
  near(vinput.status("Guitar").advice.gain, 1.23, 0.001, "what the run that ended said of the level is kept")
  paw.cmd("vinput")
  T.keys("ga")
  near(input.gain, 1.23, 0.001, "and taken with `ga` in the panel")
  paw.ui.focus("arrange")

  vinput.set("Guitar", "on", false)
  eq(
    settle(function() return vinput.status("Guitar").state == "off" end),
    true,
    "turned off, the tracker is asked to finish"
  )
  eq(run.jobs.Guitar.proc, nil, "and has")

  vinput.set("Guitar", "source", "Nowhere")
  vinput.set("Guitar", "on", true)
  eq(
    settle(function() return vinput.status("Guitar").state == "failed" end),
    true,
    "a tracker that cannot start is given up on after a few tries"
  )
  eq(vinput.status("Guitar").text, "stopped: no capture port matching 'Nowhere'", "with what it said")
  vinput.set("Guitar", "source", "Input 2")
  eq(
    settle(function() return vinput.status("Guitar").state == "running" end),
    true,
    "a change is a reason to try again"
  )
  vinput.remove("Guitar")
  eq(settle(function() return run.jobs.Guitar == nil end), true, "removing the input ends its tracker")
  paw.opt.vinput_run = false
end)

test("vinput: what the tracker prints is read, in the forms it has", function()
  load()
  local parse = vinput.kinds.gdi2m.parse_log
  local seen = parse("  2.0s  act -45.9 dBFS  q 2  notes 3 (0.0/s)  inf 2.92 mean / 4.00 max ms\n")
  eq(
    seen.level .. " " .. seen.notes .. " " .. seen.load .. " " .. tostring(seen.peak),
    "-45.9 3 2.92 nil",
    "the line a file source prints each second"
  )
  seen = parse("midi      [4] Midi-Bridge:paw:Guitar (playback), channel 1\nlistening. Ctrl-C to stop.\n")
  eq(seen.wired, true, "the wire to this program's port")
  seen =
    parse("  hops pushed 1112, dropped 3, peak queue depth 1 of 64\n  -> 34.2 dB LOW. Use --gain 51.6 to land on it\n")
  eq(seen.dropped .. " " .. tostring(seen.advice), "3 nil", "after silence its wish for gain is not taken for advice")
  seen = parse("  -> 2.5 dB HIGH. Use --gain 0.75 to land on it\n")
  eq(seen.advice.way .. " " .. seen.advice.gain, "high 0.75", "after playing it is")
  eq(
    parse("no MIDI port matches 'paw:Guitar (playback)' (or more than one does).\n").error ~= nil,
    true,
    "and what it says when it cannot start"
  )
end)

test("vinput: the ports to choose a source from come from the tracker", function()
  fresh()
  load()
  vinput.add({ name = "Guitar" })
  eq(run.sources("gdi2m", true), nil, "the first listing is not there at once")
  eq(settle(function() return run.sources("gdi2m") ~= nil end), true, "it arrives")
  eq(
    table.concat(run.sources("gdi2m"), " | "),
    "Steinberg UR22mkII  Input 2:capture_MONO | Steinberg UR22mkII  Input 1:capture_MONO",
    "the capture ports, without the entry for none"
  )
  paw.opt.vinput_gdi2m = T.scratch .. "/no-such-program"
  eq(
    vinput.kinds.gdi2m.blocked(vinput.set("Guitar", "source", "Input 2")):find("gdi2m was not found", 1, true) ~= nil,
    true,
    "a tracker that is not installed is said to be missing"
  )
end)

test("vinput: the panel shows each input's chain and is worked with the keys", function()
  fresh()
  load()
  vinput.add({ name = "Guitar", source = "Steinberg UR22mkII  Input 2:capture_MONO" })
  paw.cmd("vinput")
  eq(paw.ui.focused, "vinput", "the command opens the panel")
  -- Tall enough for the panel beside whatever earlier tests left open.
  local screen = table.concat(api.ui_snapshot(120, 90), "\n")
  eq(
    screen:find("● Guitar  UR22mkII Input 2 ▸ ×1.00 ▸ gdi2m ▸ ch 1 ▸ MIDI “Guitar”", 1, true) ~= nil,
    true,
    "the chain is drawn in a line"
  )
  eq(
    screen:find("Threshold", 1, true) ~= nil and screen:find("0.85", 1, true) ~= nil,
    true,
    "with its settings under it"
  )
  keys("jjj")
  eq(panel:current().setting.key, "gain", "j moves down the rows")
  keys("++")
  near(vinput.get("Guitar").gain, 1.1, 1e-9, "+ raises the setting a step")
  keys("3-")
  near(vinput.get("Guitar").gain, 0.95, 1e-9, "- lowers it, a count times")
  keys("x")
  eq(vinput.get("Guitar").gain, 1, "x puts it back")
  keys("o")
  eq(vinput.get("Guitar").on, false, "o turns the input off")
  keys("gg<CR>")
  eq(vinput.get("Guitar").on, true, "Enter on the heading turns it on again")
  keys("G")
  eq(panel:current().setting.key, "split", "G is the last row")
  keys("kk<CR>")
  eq(vinput.get("Guitar").attack_velocity, true, "Enter flips a switch")
  keys("t")
  eq(paw.tracks()[1].midi_input.port, "Guitar", "t makes a track that takes the input")
  paw.ui.focus("vinput")
  keys("gR")
  eq(paw.ui.message.text, "looking for audio ports", "gR looks for the ports again")
  keys("D")
  eq(#vinput.inputs, 0, "D takes the input away")
  keys("<Esc>")
  eq(paw.ui.focused, "vinput", "Esc stays, as in every view")
  keys("<C-w>p")
  eq(paw.ui.focused, "arrange", "Ctrl-w p goes back")
end)

test("vinput: the window is worked with the pointer", function()
  fresh()
  load()
  vinput.add({ name = "Guitar" })
  paw.cmd("vinput")
  eq(
    paw.ui.visible("vinput") and paw.canvas.titles.vinput,
    "Virtual inputs",
    "the panel is docked, under its title, in a graphical frontend"
  )
  local function paint() return paw.canvas.paint("vinput", 880, 520).ops end
  local function find(ops, text)
    for _, op in ipairs(ops) do
      if op[1] == "t" and op[4] == text then return op end
    end
  end
  local function click(x, y, kind)
    paw.canvas.pointer("vinput", { kind = kind or "down", x = x, y = y, button = "left" })
  end
  local ops = paint()
  eq(find(ops, "choose…") ~= nil, true, "an input with no source asks for one in its chain")

  -- The gain's slider: a press sets it, a drag moves it, a double click resets it.
  local label = find(ops, "Gain")
  local y = label[3] + 6
  click(16 + 120 + 5 + 240 / 2, y)
  near(vinput.get("Guitar").gain, 4.05, 0.051, "a press on a slider puts it there")
  paw.canvas.pointer("vinput", { kind = "move", x = 16 + 120 + 5, y = y, button = "left" })
  eq(vinput.get("Guitar").gain, 0.1, "dragging moves it")
  paw.canvas.pointer("vinput", { kind = "up", x = 16 + 120 + 5, y = y, button = "left" })
  click(16 + 120 + 40, y, "double")
  eq(vinput.get("Guitar").gain, 1, "a double click puts it back")
  eq(panel:current().setting.key, "gain", "and the keyboard's cursor is on the row that was pressed")

  -- The source, from the list of ports.
  paint()
  local box = find(paint(), "choose the guitar's input")
  click(box[2] + 20, box[3] + 4)
  settle(function() return run.sources("gdi2m") ~= nil end)
  local item = find(paint(), "   Steinberg UR22mkII  Input 2:capture_MONO")
  eq(item ~= nil, true, "a click on the source opens the ports to choose from")
  click(item[2] + 30, item[3] + 4)
  eq(vinput.get("Guitar").source, "Steinberg UR22mkII  Input 2:capture_MONO", "and a click on one takes it")
  eq(find(paint(), "UR22mkII Input 2") ~= nil, true, "the chain shows it")

  -- The switch, the on button and the buttons at the edges.
  local velocity = find(paint(), "Velocity")
  click(16 + 120 + 10, velocity[3] + 6)
  eq(vinput.get("Guitar").attack_velocity, true, "a click flips a switch")
  local on = find(paint(), "On")
  click(on[2] + 30, on[3] + 4)
  eq(vinput.get("Guitar").on, false, "the button at the top turns the input off")
  local add = find(paint(), "+ Add")
  click(add[2] + 20, add[3] + 4)
  eq(#vinput.inputs, 2, "+ Add makes another")
  local track = find(paint(), "New track from this input")
  click(track[2] + 60, track[3] + 4)
  eq(paw.tracks()[1].midi_input.port, "Guitar 2", "and a track is made for the input that is shown")
  paw.canvas.close("vinput")
end)

test("vinput: the window's menus offer the inputs", function()
  fresh()
  load()
  local labels = {}
  for index, entry in ipairs(paw.frontend.menus.timeline) do
    labels[entry.label] = index
  end
  eq(
    labels["Virtual inputs…"] ~= nil and labels["New track from a virtual input"] ~= nil,
    true,
    "the timeline's menu has both entries"
  )
  paw.frontend.act.menu("timeline", labels["New track from a virtual input"], -1, -1)
  eq(
    #vinput.inputs .. " " .. paw.tracks()[1].midi_input.port,
    "1 Guitar",
    "with no input yet one is made, and a track that takes it"
  )
  eq(paw.ui.focused, "vinput", "and the inputs are shown, for the source to be chosen")
  paw.canvas.close("vinput")
end)
