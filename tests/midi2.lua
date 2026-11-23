-- MIDI 2.0 on the way out (crates/paw-types/src/midi_form.rs): the form a
-- route sends in where the port takes no MIDI 2.0, heard back through a
-- port of the program's own MIDI input; and the editor for controller
-- moves, in the piano roll's strip and in the event list.
local T = ...
local test, eq, near, fails, fresh = T.test, T.eq, T.near, T.fails, T.fresh
local api = paw.api

-- Our port's name, told apart by the process id from those of other
-- instances running the suite at the same time, which a route by name
-- could otherwise reach.
local ffi = require("ffi")
pcall(ffi.cdef, "int getpid(void);")
local LOOP = "Loop" .. ffi.C.getpid()
local A = paw.frontend.act

local LIVE = "MIDI goes out and comes back through the system's sequencer, in real time"

local function output_named(name)
  for _, port in ipairs(paw.midi.outputs()) do
    if port.name == name then return port end
  end
end

--- Run `fn(heard)` with the sequencer open and a port of ours, "Loop", that
--- parts send to; `heard` fills with what arrives there. Nil and the
--- reason when the sequencer cannot be opened here.
local function with_loop(fn)
  -- The sequencer is shared by every process of the machine: open no port
  -- of others, so that only what our parts send to our port arrives.
  api.midi_select({})
  api.engine_restart({ midi = true })
  paw.midi.open_port(LOOP)
  local heard = {}
  local handler = paw.on("midi.in", function(event)
    if event.port == LOOP then heard[#heard + 1] = event end
  end)
  local ok, err
  if pcall(T.until_, function() return output_named("paw: " .. LOOP) end, "our port", 4000) then
    ok, err = xpcall(fn, debug.traceback, heard)
  else
    ok, err = true, "skipped: no ALSA sequencer to send MIDI through"
  end
  paw.off(handler)
  paw.midi.close_port(LOOP)
  api.engine_restart({})
  api.midi_select(nil)
  if not ok then error(err, 0) end
  return err
end

test("a MIDI output's form is checked, saved, undone and copied with the part", function()
  fresh()
  local t = paw.add_part({ name = "Hardware" })
  fails(function() t.midi_output = { port = "Synth", form = "midi3" } end, "unknown variant", "a form there is not")
  fails(function() t.midi_output = { port = "Synth", form = "mpe", members = 16 } end, "1 to 15", "a zone too wide")
  t.midi_output = { port = "Synth", channel = 2 }
  eq(t.midi_output.form, nil, "auto unless said: MIDI 2.0 where the port takes it, else plain")
  api.undo_checkpoint()
  t.midi_output = { port = "Synth", form = "mpe", members = 7 }
  api.undo_checkpoint()
  eq(paw.routes.midi_out_text(t:get()), "Synth · MPE", "said in words")
  paw.undo()
  eq(t.midi_output.form, nil, "undo takes the form back")
  paw.redo()
  eq(t.midi_output.form .. " " .. t.midi_output.members, "mpe 7", "redo brings it again")
  local path = T.scratch .. "/midi2.json"
  paw.project.save(path)
  paw.project.load(path)
  eq(paw.part("Hardware").midi_output.form, "mpe", "saved and loaded")
  eq(paw.part("Hardware"):duplicate().midi_output.members, 7, "a copy sends as the original does")
  -- Choosing another port keeps the form.
  paw.routes.set_midi_out(paw.part("Hardware").id, "Other", 3)
  eq(paw.part("Hardware").midi_output.form, "mpe", "the form stays with the route")
  fails(function() paw.routes.set_midi_out(paw.part("Hardware").id, "Other", 3, "loud") end, "auto, plain, mpe or cc14")
end)

test("the terminal and the window choose the form a part's MIDI output sends in", function()
  fresh()
  local t = paw.add_part({ name = "Hardware" })
  paw.cursor.set_part(t)
  paw.commands.exec("part.midi_out Some synth 5 mpe")
  eq(
    t.midi_output.port .. " " .. t.midi_output.channel .. " " .. t.midi_output.form,
    "Some synth 5 mpe",
    ":part.midi_out takes a form after the port and channel"
  )
  paw.commands.exec("part.midi_out Some synth cc14")
  eq(t.midi_output.form .. " " .. tostring(t.midi_output.channel), "cc14 nil", "or alone")
  local menu = paw.frontend.input_menu(t.id)
  local labels, checked = {}, nil
  for i, entry in ipairs(menu.midi_out_form) do
    labels[i] = entry.label
    if entry.checked then checked = i end
  end
  eq(#labels, 4, "the window's input menu lists the forms")
  eq(labels[checked], "MIDI 1.0 with 14-bit controllers", "the one chosen is checked")
  A.choose_input(t.id, "midi_out_form", 3)
  eq(t.midi_output.form, "mpe", "choosing one sets it")
  eq(t.midi_output.port, "Some synth", "and keeps the port")
  A.choose_input(t.id, "midi_out_channel", 4)
  eq(t.midi_output.form .. " " .. t.midi_output.channel, "mpe 3", "choosing a channel keeps the form")
  A.choose_input(t.id, "midi_out_form", 1)
  eq(t.midi_output.form, nil, "and back to MIDI 2.0 where the port takes it, which goes unsaid")
end)

test("a route in MPE plays each note of a chord on a channel of its own, bent there alone", function()
  fresh()
  return with_loop(function(heard)
    paw.project.tempo = 120
    local t = paw.add_part({ name = "Hardware" })
    local clip = t:add_clip({
      start = 0,
      length = 4,
      notes = {
        { pitch = "C4", start = 0, length = 2 },
        { pitch = "E4", start = 0, length = 2 },
        { pitch = "G4", start = 0, length = 2 },
      },
    })
    -- The E a semitone up, half a beat in.
    clip:set_controls({ { start = 0.5, type = "bend", key = "E4", value = 1 / 48 } })
    t.midi_output = { port = "paw: " .. LOOP, form = "mpe", members = 4 }
    paw.transport.play()
    local function ons()
      local out = {}
      for _, e in ipairs(heard) do
        if e.type == "note_on" then out[e.pitch] = e.channel end
      end
      return out
    end
    T.until_(function()
      for _, e in ipairs(heard) do
        if e.type == "bend" and e.value > 0 then return true end
      end
    end, "what was sent to come back", 8000)
    paw.transport.stop()
    local on = ons()
    eq(string.format("%s %s %s", on[60], on[64], on[67]), "2 3 4", "the chord on member channels 2, 3 and 4")
    local bend
    for _, e in ipairs(heard) do
      if e.type == "bend" and e.value > 0 then bend = e end
    end
    eq(bend and bend.channel, on[64], "the E's own bend is its channel's pitch bend")
    near(bend.value * 48, 1, 0.01, "a semitone, over the zone's 48")
    local announced = false
    for _, e in ipairs(heard) do
      if e.type == "cc" and e.number == 6 and e.channel == 1 then announced = math.floor(e.value * 127 + 0.5) == 4 end
    end
    eq(announced, true, "the zone was announced on channel 1, with its four member channels")
    T.until_(function()
      local offs = 0
      for _, e in ipairs(heard) do
        if e.type == "note_off" then offs = offs + 1 end
      end
      return offs >= 3
    end, "what was sent to come back", 4000)
    local offs = {}
    for _, e in ipairs(heard) do
      if e.type == "note_off" then offs[e.pitch] = e.channel end
    end
    eq(string.format("%s %s %s", offs[60], offs[64], offs[67]), "2 3 4", "stopping ends each note on its channel")
  end)
end, { live = LIVE })

test("a route with 14-bit controllers sends the fine part of control changes below 32", function()
  fresh()
  return with_loop(function(heard)
    paw.project.tempo = 120
    local t = paw.add_part({ name = "Hardware" })
    local clip = t:add_clip({ start = 0, length = 2, notes = {} })
    -- Halfway, and one fourteen-bit step past it.
    clip:set_controls({ { start = 0.25, type = "cc", number = 1, value = (8192 + 1) / 16383 } })
    t.midi_output = { port = "paw: " .. LOOP, channel = 3, form = "cc14" }
    paw.transport.play()
    T.until_(function()
      for _, e in ipairs(heard) do
        if e.type == "cc" and e.number == 33 then return true end
      end
    end, "what was sent to come back", 8000)
    paw.transport.stop()
    local coarse, fine
    for _, e in ipairs(heard) do
      if e.type == "cc" and e.number == 1 then coarse = e end
      if e.type == "cc" and e.number == 33 then fine = e end
    end
    eq(coarse and coarse.channel, 3, "the coarse part on its channel")
    eq(fine and fine.channel, 3, "and the fine part, on 33")
    eq(
      math.floor(coarse.value * 127 + 0.5) * 128 + math.floor(fine.value * 127 + 0.5),
      8193,
      "together the fourteen bits"
    )
  end)
end, { live = LIVE })

-- The editor for controller moves.

local function starts(list)
  local out = {}
  for i, m in ipairs(list) do
    out[i] = string.format("%g", m.start)
  end
  return table.concat(out, " ")
end

--- The moves of `clip` whose places are `places`.
local function picked(clip, places)
  local all, out = clip:controls(), {}
  for i, place in ipairs(places) do
    out[i] = all[place]
  end
  return out
end

local function moves_clip()
  fresh()
  paw.project.tempo = 120
  paw.opt.note_grid, paw.opt.note_snap = 0.25, true
  local t = paw.add_part({ name = "Keys" })
  local clip = t:add_clip({ start = 0, length = 8, notes = { { pitch = "C4", start = 0, length = 1 } } })
  clip:set_controls({
    { start = 0, type = "cc", number = 1, value = 0.2 },
    { start = 1, type = "cc", number = 1, value = 0.4 },
    { start = 2, type = "cc", number = 1, value = 0.6 },
    { start = 3, type = "cc", number = 1, value = 0.8 },
    { start = 1, type = "bend", value = 0.5 },
    { start = 1.5, type = "cc", number = 74, value = 0.9 },
  })
  return clip
end

test("controller moves in the strip are chosen with a click or a box, moved, and taken away", function()
  local clip = moves_clip()
  local id = clip.id
  eq(
    A.select_controls(id, "cc", 1, 0.5, 0, 2.5, 1, "only"),
    2,
    "a box over two beats chooses the modulation moves there"
  )
  eq(starts(picked(clip, paw.controls.chosen(id))), "1 2", "and not the wheel or another controller in it")
  eq(A.select_controls(id, "cc", 1, 0, 0.5, 8, 1, "only"), 2, "a box can take only the high ones")
  eq(starts(picked(clip, paw.controls.chosen(id))), "2 3", "those above the middle")
  local first = paw.controls.chosen(id)[1]
  A.select_controls(id, "cc", 1, 0, 0, 0.1, 1, "add")
  eq(#paw.controls.chosen(id), 3, "Shift adds to them")
  A.select_control(id, first, "toggle")
  eq(starts(picked(clip, paw.controls.chosen(id))), "0 3", "Ctrl takes one out")
  -- Dragged a beat and a bit later and a tenth up: the first lands on the grid.
  local stamp = api.clip_get(id).control_stamp
  A.move_controls(id, 1.1, 0.1)
  eq(api.clip_get(id).control_stamp ~= stamp, true, "the clip says its moves changed, for the window to fetch them")
  local moved = picked(clip, paw.controls.chosen(id))
  eq(starts(moved), "1 4", "moved on, still the chosen ones")
  near(moved[1].value, 0.3, 1e-9, "and up")
  near(moved[2].value, 0.9, 1e-9, "both of them")
  A.move_controls(id, 0, 5)
  near(picked(clip, paw.controls.chosen(id))[2].value, 1, 1e-9, "no higher than the top")
  api.undo_checkpoint()
  eq(A.remove_chosen_controls(id), 2, "Delete takes the chosen away")
  api.undo_checkpoint()
  local left = {}
  for _, m in ipairs(clip:controls()) do
    left[#left + 1] = m.type .. (m.number or "") .. "@" .. m.start
  end
  eq(table.concat(left, " "), "cc1@1 bend@1 cc74@1.5 cc1@2", "the rest stay")
  paw.undo()
  eq(#clip:controls(), 6, "undo brings them back")
  eq(#paw.controls.chosen(id), 0, "and an edit made otherwise lets go of the chosen")
  -- The piano roll's x takes chosen moves away too.
  paw.ui.views:get("pianoroll"):edit(clip)
  A.select_all_controls(id, "bend")
  eq(#paw.controls.chosen(id), 1, "every move of the strip's kind")
  paw.keymap.feed("x")
  eq(#clip:controls(), 5, "x in the piano roll deletes the chosen moves")
  eq(#clip:notes(), 1, "and not the note under the cursor")
end)

test("a line of controller moves replaces those between its ends, a move to each grid step", function()
  local clip = moves_clip()
  local id = clip.id
  eq(A.line_controls(id, "cc", 1, 2, 1, 1, 0), 5, "from beat 1 to 2 in quarter beats, either way round")
  local line = {}
  for _, m in ipairs(clip:controls()) do
    if m.type == "cc" and m.number == 1 then line[#line + 1] = string.format("%g=%g", m.start, m.value) end
  end
  eq(table.concat(line, " "), "0=0.2 1=0 1.25=0.25 1.5=0.5 1.75=0.75 2=1 3=0.8", "a ramp, the moves outside it kept")
  eq(#paw.controls.chosen(id), 5, "the line is then chosen, to move it")
  -- The wheel rests in the middle of the strip.
  A.line_controls(id, "bend", nil, 4, 0.5, 5, 1, true)
  local bends = {}
  for _, m in ipairs(clip:controls()) do
    if m.type == "bend" and m.start >= 4 then bends[#bends + 1] = m end
  end
  eq(#bends, 33, "off the grid, a move to each 32nd of a beat")
  near(bends[1].value, 0, 1e-9, "from rest")
  near(bends[#bends].value, 1, 1e-9, "to the top")
  paw.ui.views:get("pianoroll"):edit(clip)
  paw.commands.exec("controls.line cc 7 0 127")
  local volume = {}
  for _, m in ipairs(clip:controls()) do
    if m.type == "cc" and m.number == 7 then volume[#volume + 1] = m end
  end
  eq(#volume, 32, ":controls.line draws across the whole clip without a selection")
  near(volume[#volume].value, 1, 1e-9, "up to 127")
end)

test("the event list shows every note and move in time order and changes each cell in place", function()
  fresh()
  paw.project.tempo = 120
  local t = paw.add_part({ name = "Keys" })
  local clip = t:add_clip({
    start = 4,
    length = 4,
    notes = {
      { pitch = "C4", start = 0, length = 1, velocity = 100 },
      { pitch = "E4", start = 1, length = 0.5, velocity = 90 },
    },
  })
  clip:set_controls({
    { start = 0.5, type = "cc", number = 74, value = 0.5 },
    { start = 1, type = "bend", key = "E4", value = 1 / 48 },
  })
  local id = clip.id
  local function table_of()
    local out = {}
    for i, row in ipairs(paw.controls.rows(id)) do
      local c = paw.controls.cells(id, row)
      out[i] = table.concat({ c.time, c.kind, c.which, c.value, c.length }, "|")
    end
    return out
  end
  local rows = table_of()
  eq(rows[1], "2.1.00|note|C4|100|1", "a note: where, what, how hard, how long")
  eq(rows[2], "2.1.50|cc|74|63.5|", "a controller in seven-bit steps, finer ones as decimals")
  eq(rows[3], "2.2.00|note|E4|90|0.5", "notes before moves at the same time")
  eq(rows[4], "2.2.00|bend|E4|+1.00 st|", "a note's own bend in semitones")
  local function row(n) return paw.controls.rows(id)[n] end
  paw.controls.edit(id, row(2), "value", "100")
  near(clip:controls()[1].value, 100 / 127, 1e-9, "a value typed in")
  paw.controls.edit(id, row(4), "value", "-2 st")
  near(clip:controls()[2].value, -2 / 48, 1e-9, "a bend in semitones")
  paw.controls.edit(id, row(1), "which", "D4")
  eq(clip:notes()[1].pitch, 62, "a note's pitch by name")
  paw.controls.edit(id, row(1), "time", "2.3.50")
  near(clip:notes()[2].start, 2.5, 1e-9, "a time as bar.beat.hundredths moves the note")
  eq(table_of()[1], "2.1.50|cc|74|100|", "the list is in time order again")
  fails(function() paw.controls.edit(id, row(1), "kind", "bend") end, "kind stays", "a row's kind")
  fails(function() paw.controls.edit(id, row(1), "time", "12.1") end, "outside the clip", "a time past the clip")
  fails(
    function() paw.controls.edit(id, row(1), "value", "loud") end,
    "a value is a number",
    "a value that is no number"
  )
  paw.controls.remove_row(id, row(1))
  eq(#clip:controls(), 1, "a move taken away")
  paw.controls.add(id, 3, "cc", 11)
  local all = table_of()
  eq(all[#all], "2.4.00|cc|11|0|", "a move added")
end)

test("the event list floats over the terminal, its keys change a cell, and the window opens it alone", function()
  fresh()
  local t = paw.add_part({ name = "Keys" })
  local clip =
    t:add_clip({ start = 0, length = 4, notes = { { pitch = "C4", start = 0, length = 1, velocity = 100 } } })
  clip:set_controls({ { start = 1, type = "cc", number = 1, value = 0 } })
  paw.ui.views:get("pianoroll"):edit(clip)
  paw.keymap.feed("E")
  eq(paw.ui.float and paw.ui.float.name, "eventlist", "E in the piano roll lists its clip's events")
  local list = paw.ui.views:get("eventlist")
  list.row, list.column = 1, 4
  paw.keymap.feed("j<CR><C-u>64<CR>")
  near(clip:controls()[1].value, 64 / 127, 1e-9, "Enter asks for the cell's text, and sets it")
  paw.keymap.feed("kx")
  eq(#clip:notes(), 0, "x deletes the row under the cursor")
  paw.keymap.feed("q")
  eq(paw.ui.float, nil, "q closes it")
  A.open_event_list(clip.id)
  local open = false
  for _, w in ipairs(paw.canvas.windows()) do
    open = open or w.name == "eventlist"
  end
  eq(open, true, "the window's piano roll opens it in a window of its own")
  paw.canvas.close("eventlist")
end)
