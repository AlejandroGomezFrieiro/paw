-- Tests of step input in the piano roll (`I`, paw/step.tl and
-- paw/roll_draw.tl): keys of a MIDI controller, sent with paw.midi.inject
-- from test ports of the null backend. Loaded by tests/suite.lua.
local T = ...
local meter = T.meter
local eq, fresh, melody = T.eq, T.fresh, T.melody
local api = paw.api
local draw = paw.roll_draw
local roll = paw.ui.views:get("pianoroll")

local function test(name, fn)
  T.test(name, function()
    local ok, err = xpcall(fn, debug.traceback)
    paw.keymap.feed("<Esc><Esc>")
    while paw.ui.float do
      paw.ui.close()
    end
    paw.keymap.feed("<Esc>")
    paw.step.learn_cancel()
    for _, b in ipairs(paw.step.bindings()) do
      if not b.saved then paw.step.unbind(b.source) end
    end
    paw.step.use()
    api.midi_test_ports({})
    roll:set_step(nil)
    paw.ui.hide("pianoroll")
    paw.ui.focus("arrange")
    if not ok then error(err, 0) end
  end)
end

local function typed(text)
  for _, key in ipairs(paw.keymap.parse(text)) do
    paw.keymap.feed(key)
    api.undo_checkpoint()
  end
end

--- A track with an empty clip, open in the piano roll on C4 at its start,
--- and a controller on the port "Test Keys" (and pads on "Test Pads").
local function empty(device)
  fresh()
  paw.ui.focus("arrange")
  paw.opt.note_grid, paw.opt.velocity = 0.25, 100
  api.midi_test_ports({ "Test Keys", "Test Pads" })
  local track = paw.add_track({ name = "Lead" })
  track:add_device(device or "synth")
  local clip = track:add_clip({ name = "tune", start = 0, length = 4 })
  api.undo_checkpoint()
  paw.ui.show("pianoroll")
  paw.ui.focus("pianoroll")
  roll:edit(clip)
  roll:set(60, 0)
  roll:set_step(nil)
  return clip, track
end

local function down(pitch, velocity, port)
  paw.midi.inject({ type = "note_on", pitch = pitch, velocity = velocity or 100, port = port or "Test Keys" })
end
local function up(pitch, port) paw.midi.inject({ type = "note_off", pitch = pitch, port = port or "Test Keys" }) end
--- A key played and released.
local function play(pitch, velocity, port)
  down(pitch, velocity, port)
  up(pitch, port)
  paw.flush()
end

local function velocities(clip)
  local out = {}
  for i, n in ipairs(clip:notes()) do
    out[i] = n.pitch .. ":" .. n.velocity
  end
  return table.concat(out, " ")
end

test(
  "step input: I, keys and chords from the controller, = the step, Space, Backspace, Escape one undo step",
  function()
    local clip = empty()
    typed("I")
    eq(draw.stepping(), true, "I in normal mode starts step input")
    eq(draw.label():match("^STEP"), "STEP", "the title says STEP: " .. draw.label())
    play(60, 90)
    eq(select(2, draw.text()), "60@0+0.25", "a key enters a note one step long, at the caret")
    down(64, 80)
    down(67, 70)
    paw.flush()
    eq(draw.label(), "STEP holding E4 G4", "the title names the keys held")
    up(64)
    up(67)
    paw.flush()
    eq(
      table.concat({ draw.text() }, " | "),
      "60@0+0.25 | 64@0.25+0.25 67@0.25+0.25",
      "keys held together are one chord"
    )
    typed("=8")
    eq(select(2, draw.text()), "64@0.25+0.5 67@0.25+0.5", "= sets the length of the chord")
    play(72)
    eq(select(2, draw.text()), "72@0.75+0.5", "and of the notes that follow")
    typed("<Space>2")
    play(74)
    eq(
      table.concat({ draw.text() }, " | "):match("72.*$"),
      "72@0.75+0.5 74@1.75+0.5 | 74@2.25+0.5",
      "Space rests one step; a count enters the key that many times"
    )
    typed("<BS>")
    eq(select(2, draw.text()), "74@1.75+0.5", "Backspace takes back the note entered last")
    typed("<Esc>")
    eq(paw.ui.message.text, "wrote 5 notes", "Escape writes them")
    eq(melody(clip), "60@0+0.25 64@0.25+0.5 67@0.25+0.5 72@0.75+0.5 74@1.75+0.5", "all the notes")
    eq(velocities(clip):match("^60:90 64:80 67:70"), "60:90 64:80 67:70", "with the velocity of each key")
    typed("u")
    eq(#clip:notes(), 0, "one undo step")
  end
)

test("step input: I in the pencil, the track's port only, and nothing while playing", function()
  local clip, track = empty()
  track.midi_input = { port = "Test Keys" }
  typed("ill")
  typed("I")
  play(64, 100, "Test Pads")
  eq(select(2, draw.text()), "60@0+0.5", "I in the pencil keeps the pen; a key of another port does not enter")
  play(64)
  eq(table.concat({ draw.text() }, " | "), "60@0+0.5 | 64@0.5+0.25", "a key of the track's port enters after the pen")
  paw.transport.play()
  paw.flush()
  eq(draw.label(), "STEP (paused: playing)", "while the song plays, the keys only sound")
  play(65)
  paw.transport.stop()
  paw.flush()
  eq(select(2, draw.text()), "64@0.5+0.25", "and enter nothing")
  typed("I")
  eq(draw.stepping(), false, "I again turns step input off")
  play(65)
  eq(select(2, draw.text()), "64@0.5+0.25", "and the keys enter nothing")
  typed("<Esc>")
  eq(melody(clip), "60@0+0.5 64@0.5+0.25", "the notes drawn and played")
end)

test("step input: with no MIDI input, I says why and opens the track's MIDI inputs", function()
  empty()
  api.midi_test_ports({})
  typed("I")
  eq(paw.ui.message.text:find("no MIDI input (no MIDI port is", 1, true) ~= nil, true, paw.ui.message.text)
  local state = paw.pick.state()
  eq(state and state.title, "Input of Lead", "the list of the track's inputs opens")
  eq(table.concat(state.matches, "\n"):find("Monitor", 1, true), nil, "at its MIDI part")
  paw.keymap.feed("<Esc>")
  eq(draw.stepping(), true, "step input stays on")
  play(62)
  eq(select(2, draw.text()), "62@0+0.25", "and a key that arrives later enters")
end)

-- Controls of the controller (paw.step.bind, :step.learn, :step.controls) ------

local function pedal(pressed, port)
  paw.midi.inject({ type = "cc", number = 64, value = pressed and 1 or 0, port = port or "Test Keys" })
  paw.flush()
end

test("step input: the pedal rests with no key held, and ties the keys held", function()
  local clip = empty()
  typed("I")
  pedal(true)
  pedal(false)
  eq(draw.label():match("^STEP rest"), "STEP rest", "the title says what the pedal did: " .. draw.label())
  down(60)
  paw.flush()
  pedal(true)
  pedal(false)
  up(60)
  paw.flush()
  eq(select(2, draw.text()), "60@0.25+0.5", "a rest of one step, then the pedal held with C4 makes it a step longer")
  typed("<Esc>")
  eq(melody(clip), "60@0.25+0.5", "Escape writes it")
  typed("u")
  eq(#clip:notes(), 0, "one undo step")
end)

-- An instrument that sounds from its first note on.
local NOTED = [[
local dsp = require("paw.dsp")
local dev = dsp.device { category = "instrument" }
local level = 0
function dev.process(b)
  for i = 0, b.nevents - 1 do
    if b.events[i].type == dsp.NOTE_ON then level = 0.5 end
  end
  for i = 0, b.frames - 1 do b.left[i], b.right[i] = level, level end
end
return dev
]]

test("step input: :step.learn binds a pad, which then rests and reaches no track", function()
  local dir = T.scratch .. "/step-noted"
  os.execute("mkdir -p '" .. dir .. "'")
  T.write_file(dir .. "/step_noted.lua", NOTED)
  paw.luadev.add_dir(dir)
  local clip, track = empty("lua:step_noted")
  typed(":step.learn tie<CR><Esc>")
  eq(paw.step.learning, nil, "Esc stops the wait")
  typed(":step.learn rest<CR>")
  play(36, 100, "Test Pads")
  eq(
    paw.ui.message.text,
    "Test Pads ch 1 C2 (note 36) now does rest in step input",
    "learned by port, channel and note"
  )
  typed("I")
  play(36, 100, "Test Pads")
  eq(draw.label():match("^STEP rest"), "STEP rest", "the pad rests: " .. draw.label())
  T.next_block(20)
  eq(meter(track) <= 0.005, true, "the Lua device on the track got no note")
  play(36, 100, "Test Keys")
  T.until_(function() return meter(track) > 0.02 end, "the key of the other port to sound")
  typed("<Esc>")
  eq(melody(clip), "36@0.25+0.25", "a rest, then C2 from the keyboard")
end)

test("step input: a control that types keys sets the step to an eighth triplet", function()
  empty()
  paw.step.bind({ port = "Test Pads", note = 40 }, { keys = "=8t" })
  typed("I")
  play(40, 100, "Test Pads")
  eq(draw.label():find("(=8t)", 1, true) ~= nil, true, "the STEP title shows it: " .. draw.label())
end)

local function bound(action)
  for _, b in ipairs(paw.step.bindings()) do
    if b.action == action then return b end
  end
end

test("step input: :step.learn keeps the control in the file; --clean reads and writes none", function()
  local file = T.scratch .. "/step-controls.json"
  paw.step.use(file)
  empty()
  typed(":step.learn back<CR>")
  play(37, 100, "Test Pads")
  eq(api.json_decode(T.read_file(file)).bindings[2].action, "back", "written to the file")
  paw.step.unbind(bound("back").source)
  paw.step.load()
  eq(bound("back").source.note, 37, "read from the file again")
  eq(api.env().clean, true, "the suite runs with --clean")
  paw.step.use()
  eq(paw.step.file, nil, "with --clean there is no file")
  eq(bound("back"), nil, "and nothing is read")
  typed(":step.learn back<CR>")
  play(37, 100, "Test Pads")
  eq(bound("back").saved, true, "a control learned")
  eq(io.open(api.env().state_dir .. "/step-controls.json"), nil, "is written nowhere")
end)

test("step input: :step.controls lists the controls, and Alt-d removes one from the file", function()
  local file = T.scratch .. "/step-controls-list.json"
  paw.step.use(file)
  empty()
  typed(":step.learn rest<CR>")
  play(36, 100, "Test Pads")
  typed(":step.controls<CR>")
  local state = paw.pick.state()
  eq(state.title, "Step input controls", "the list opens")
  local lines = table.concat(state.matches, "\n")
  eq(lines:find("cc 64 (pedal)", 1, true) ~= nil, true, "with the pedal: " .. lines)
  eq(lines:find("C2 (note 36)", 1, true) ~= nil, true, "and the pad learned")
  paw.keymap.feed("note 36")
  paw.keymap.feed("<A-d>")
  paw.keymap.feed("<Esc>")
  local saved = api.json_decode(T.read_file(file)).bindings
  eq(#saved, 1, "the file keeps one control")
  eq(saved[1].cc, 64, "the pedal")
end)

test("step input: an action that the target does not have says so", function()
  empty()
  paw.step.target("bare", {
    active = function() return true end,
    note = function() end,
    release = function() end,
    actions = {},
  })
  T.after(function()
    paw.step.untarget("bare")
    paw.step.refresh()
  end)
  paw.step.refresh()
  paw.step.bind({ port = "Test Pads", note = 50 }, "legato")
  play(50, 100, "Test Pads")
  eq(paw.ui.message.text, "not here: legato", "the control says it")
end)
