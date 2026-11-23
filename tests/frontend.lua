-- What a graphical frontend is told, and what its pointer does: the same
-- for every frontend, so it is tested here and not in one of them.
local T = ...
local advance = T.advance
local test, eq, near, fresh = T.test, T.eq, T.near, T.fresh
local paw = require("paw")
local api = paw.api
local act = paw.frontend.act

local function song()
  fresh()
  paw.opt.grid = 1
  local a, b = paw.add_track({ name = "a" }), paw.add_track({ name = "b" })
  a:add_device("synth")
  local clip = a:add_clip({
    start = 4,
    length = 4,
    name = "riff",
    notes = {
      { pitch = 60, start = 0, length = 1, velocity = 100 },
      { pitch = 64, start = 1, length = 1, velocity = 80 },
    },
  })
  paw.flush()
  return a, b, clip
end

test("the window is told how many frames a second to draw while the song plays", function()
  eq(paw.frontend.state(-1).window_fps, "auto", "auto at first: the window knows its renderer")
  paw.commands.exec("set window_fps=10")
  eq(paw.frontend.state(-1).window_fps, 10, ":set window_fps=10")
  eq(pcall(function() paw.opt.window_fps = 0 end), false, "not 0")
  eq(pcall(function() paw.opt.window_fps = "fast" end), false, "a number or auto")
  paw.opt.window_fps = "auto"
  eq(paw.frontend.state(-1).window_cache, "auto", "the still part in a texture, auto")
  paw.commands.exec("set window_cache=false")
  eq(paw.frontend.state(-1).window_cache, false, ":set window_cache=false draws it straight")
  paw.opt.window_cache = "auto"
end)

test("the frontend is told colours, chains, both meter sides and when notes change", function()
  local a, _, clip = song()
  local state = paw.frontend.state(-1)
  eq(state.tracks[1].color, paw.draw.track_colour(a:get(), 1), "a track's colour")
  eq(state.tracks[1].chain, "Synth", "what it goes through")
  eq(#state.levels, 2 * #state.tracks, "a level for each side of each track")
  eq(type(state.clock), "string", "the time in minutes and seconds")
  local stamp = state.clips[1].stamp
  eq(type(stamp), "string", "a stamp for the clip's notes")
  eq(paw.frontend.state(-1).clips[1].stamp, stamp, "the same while nothing changes")
  clip:set_note(1, { velocity = 90 })
  eq(paw.frontend.state(-1).clips[1].stamp ~= stamp, true, "another when a note does")
  local flat = paw.frontend.preview(clip.id)
  eq(#flat, 6, "the notes for the clip's picture, three numbers each")
  eq(flat[3], 60, "start, length, pitch")
  -- The piano roll as a window is sent it: notes in the track's colour,
  -- with how hard each is played.
  paw.ui.views:get("pianoroll"):edit(clip)
  local notes = T.roll_notes()
  eq(notes[1].props.color, state.tracks[1].color, "the notes in the track's colour")
  eq(notes[2].props.velocity, 80, "and how hard each note is played")
  paw.ui.hide("pianoroll")
  paw.ui.focus("arrange")
  a.color = "#abcdef"
  eq(paw.frontend.state(-1).tracks[1].color, "#abcdef", "a colour of the track's own is passed on")
end)

test("the pointer selects, moves, copies, resizes and makes clips", function()
  local a, b, clip = song()
  act.select(b.id, 2.4)
  eq(paw.cursor.track_id(), b.id, "a click on a lane puts the cursor on its track")
  eq(paw.cursor.beat, 2, "at the beat, on the grid")
  act.select_clip(clip.id, 5.2)
  eq(paw.cursor.track_id(), a.id, "a click on a clip puts it on the clip's track")
  eq(paw.frontend.state(-1).modal.clip, clip.id, "and the frontend is told which clip that is")

  act.move_clip(clip.id, 8.3, b.id)
  eq(clip.start, 8, "a dragged clip lands on the grid")
  eq(clip:get().track, b.id, "on the track it was dropped on")
  act.move_clip(clip.id, -3, nil)
  eq(clip.start, 0, "and never before the start")
  local copy = paw.clip(act.move_clip(clip.id, 12, a.id, true))
  eq(clip.start, 0, "dragged with copy held, the clip stays")
  eq(copy.start, 12, "and a copy is dropped")
  eq(#copy:notes(), 2, "with its notes")
  eq(copy:get().track, a.id, "where it was dropped")

  act.resize_clip(clip.id, 6.4)
  eq(clip.length, 6, "the right edge is dragged to a length on the grid")
  act.resize_clip(clip.id, 0.1)
  eq(clip.length, 1, "never under one step")

  local made = paw.clip(act.add_clip(b.id, 21.5))
  eq(made.start, 20, "a double click on a lane makes a clip in that bar")
  eq(made.length, 4, "a bar long")

  act.open_clip(clip.id)
  eq(
    paw.ui.visible("pianoroll") and paw.ui.views:get("pianoroll"):clip().id,
    clip.id,
    "a double click on a clip opens its notes"
  )
  act.close_roll()
  eq(paw.ui.visible("pianoroll"), false, "and they close again")
  eq(paw.ui.focused, "arrange", "leaving the arrange view with the keyboard")
end)

test("menus act on what was clicked, and dragging selects or loops", function()
  local a, b, clip = song()
  act.select(b.id, 0)
  act.clip_command(clip.id, 6, "clip.split")
  eq(#a:clips(), 2, "a command from a clip's menu is run on that clip")
  eq(a:clips()[2].start, 6, "where it was clicked")
  act.clip_command(a:clips()[1].id, nil, "clip.mute")
  eq(a:clips()[1].muted, true, "another")
  act.track_command(b.id, "track.color teal")
  eq(b.color, require("paw.theme").hues[6], "and one from a track's menu on that track")
  act.color_track(b.id, "none")
  eq(b.color, nil, "the colour menu")
  act.rename_track(b.id, "  drums ")
  eq(b.name, "drums", "a new name, trimmed")
  paw.flush()
  local revision = paw.frontend.revision
  act.move_track(b.id, 1)
  eq(api.track_list()[1], b.id, "a header dragged to the top")
  paw.flush()
  eq(paw.frontend.revision > revision, true, "and the frontend hears that the order changed")

  act.set_loop(8.2, 3.9)
  eq(paw.transport.loop_start, 4, "a drag along the ruler loops that stretch, either way round")
  eq(paw.transport.loop_end, 8, "to the grid")
  eq(paw.transport.loop_enabled, true, "and turns the loop on")
  act.set_loop(2.1, 2.3)
  eq(paw.transport.loop_start, 4, "a click on the ruler leaves the loop alone")
  act.set_loop_edge("start", 2.2)
  act.set_loop_edge("end", 10.4)
  eq(paw.transport.loop_start .. " " .. paw.transport.loop_end, "2 10", "the loop's edges are dragged, to the grid")
  act.set_loop_edge("start", 12)
  eq(paw.transport.loop_start .. " " .. paw.transport.loop_end, "9 10", "and stay a step apart")
  act.ruler_click(6.3)
  eq(
    paw.cursor.beat .. " " .. paw.transport.position,
    "6 6",
    "a click on the ruler puts the edit cursor and the playhead"
  )

  act.select_range(1, 4, 2, 8)
  local sel = paw.frontend.state(-1).modal.selection
  eq(sel ~= nil, true, "a drag across lanes selects")
  eq(sel.r0 .. " " .. sel.r1, "1 2", "those tracks")
  eq(sel.c0 .. " " .. sel.c1, "4 8", "over that stretch")
  act.keys("<Del>")
  eq(#a:clips(), 0, "and a key, or the menu, acts on the selection")
  act.select(a.id, 0)
  eq(paw.frontend.state(-1).modal.selection, nil, "a click lets go of it")
end)

test("the pointer edits notes, velocities, the mixer, automation and devices", function()
  local a, _, clip = song()
  eq(act.add_note(clip.id, 67, 2.1, 0.5), 3, "a click in the roll adds a note on the grid")
  eq(clip:notes()[3].start, 2, "where it was clicked")
  eq(act.add_note(clip.id, 67, 2.1), nil, "not on top of another")
  eq(act.add_note(clip.id, 67, 9), nil, "nor past the end of the clip")
  eq(act.move_note(clip.id, 1, 3.26, 72), 3, "a dragged note says where it is now")
  eq(clip:notes()[3].pitch, 72, "at its new pitch")
  eq(clip:notes()[3].start, 3.25, "and time")
  act.resize_note(clip.id, 3, 0.01)
  eq(clip:notes()[3].length, paw.opt.note_grid, "an edge is dragged to at least one step")
  act.set_velocity(clip.id, 1, 300)
  eq(clip:notes()[1].velocity, 127, "a velocity is dragged within its range")
  act.remove_note(clip.id, 1)
  eq(#clip:notes(), 2, "and a note is removed")

  act.set_volume(a.id, 20)
  eq(a.volume, 6, "a fader stops at the top")
  act.set_pan(a.id, -0.5)
  eq(a.pan, -0.5, "pan")
  act.toggle(a.id, "solo")
  eq(a.solo, true, "a flag")

  local lane = paw.lane(act.lane(a.id, "volume"))
  eq(act.lane(a.id, "volume"), lane.id, "the volume lane is made once")
  act.add_point(lane.id, 2.2, 0.5)
  act.add_point(lane.id, 4, 1)
  eq(#lane:points(), 2, "points are added to the volume lane")
  eq(lane:points()[1][2], -27, "at a height in the fader's travel")
  eq(lane:points()[2][2], 6, "up to its top")
  act.move_point(lane.id, 1, 3, 0)
  eq(lane:points()[1][1], 3, "moved")
  act.remove_point(lane.id, 1)
  eq(#lane:points(), 1, "and removed")

  local synth = a:devices()[1]
  act.set_param(synth.id, "cutoff", 0)
  eq(synth:get().params.cutoff, 20, "a slider at the left is the parameter's lowest")
  act.reset_param(synth.id, "cutoff")
  eq(synth:get().params.cutoff, 4000, "a double click puts it back")
  act.toggle_bypass(synth.id)
  eq(synth:get().bypass, true, "bypass")
  local delay = paw.device(act.add_device("delay"))
  act.move_device(delay.id, -1)
  eq(a:devices()[1].id, delay.id, "a device is moved up its chain")
  T.fails(function() act.set_param(synth.id, "nope", 0) end, "no parameter", "a parameter that is not there")
end)

test("any parameter is automated, and lanes are drawn with a pencil", function()
  local a = song()
  local synth = a:devices()[1]
  local pan = paw.lane(act.lane(a.id, "pan"))
  local cutoff = paw.lane(act.lane(a.id, "param", synth.id, "cutoff"))
  eq(#a:lanes(), 2, "a lane for pan and one for a parameter")
  local lanes = paw.frontend.state(-1).tracks[1].lanes
  eq(lanes[1].name, "Pan", "the frontend is told what each lane moves")
  eq(lanes[2].name, "Synth · cutoff", "by name")
  eq(lanes[1].lo .. " " .. lanes[1].hi, "-1 1", "and the range to draw it over")
  eq(lanes[2].lo .. " " .. lanes[2].hi, "20 20000", "which is the parameter's own")

  act.add_point(pan.id, 0, 0.5)
  eq(pan:points()[1][2], 0, "half way up a pan lane is the centre")
  act.add_point(cutoff.id, 4, 1)
  eq(cutoff:points()[1][2], 20000, "the top of a parameter lane is its highest value")

  -- A stroke of the pencil from beat 1 to beat 3, rising.
  act.add_point(pan.id, 2, 1)
  act.add_point(pan.id, 6, 0)
  local stroke = {}
  for i = 0, 40 do
    stroke[#stroke + 1] = { 1 + i * 0.05, i / 40 }
  end
  act.draw_lane(pan.id, stroke)
  local points = pan:points()
  eq(points[1][1], 0, "what was before the stroke stays")
  eq(points[#points][1], 6, "and what was after it")
  local inside, rising = 0, true
  for i, p in ipairs(points) do
    if p[1] >= 1 - 1e-9 and p[1] <= 3 + 1e-9 then
      inside = inside + 1
      if i > 1 and points[i - 1][1] >= 1 and p[2] < points[i - 1][2] then rising = false end
    end
  end
  eq(inside >= 8 and inside <= 10, true, "the stroke is thinned to a quarter of a grid step: " .. inside)
  eq(rising, true, "and keeps its shape")
  near(pan:value_at(3), 1, 1e-6, "ending where the pencil was lifted")
  eq(pan:value_at(2) > -0.1 and pan:value_at(2) < 0.1, true, "the point that was under it is gone")

  act.toggle_lane(pan.id)
  eq(pan.enabled, false, "a lane is switched off")
  act.clear_lane(pan.id)
  eq(#pan:points(), 0, "and emptied")
end)

test("controller moves are drawn into a clip with a pencil", function()
  local _, _, clip = song()
  paw.opt.note_grid = 0.25
  local stroke = {}
  for i = 0, 20 do
    stroke[#stroke + 1] = { i * 0.05, 0.5 + i / 40 }
  end
  act.draw_controls(clip.id, "bend", nil, stroke)
  local controls = clip:controls()
  eq(#controls, 5, "one move to a step of the note grid")
  eq(controls[1].type, "bend", "of the kind drawn")
  eq(controls[1].value, 0, "the wheel rests half way up")
  eq(controls[5].value, 1, "and is at its top at the top")
  act.draw_controls(clip.id, "cc", 1, { { 0, 0.25 }, { 0.5, 0.75 } })
  eq(#clip:controls(), 7, "another kind beside it")
  act.draw_controls(clip.id, "bend", nil, { { 0, 0.5 }, { 2, 0.5 } })
  local flat = true
  for _, c in ipairs(clip:controls()) do
    if c.type == "bend" and c.value ~= 0 then flat = false end
  end
  eq(flat, true, "drawing over a stretch replaces what was there")
  eq(#paw.controls.chosen(clip.id) >= 0 and #clip:controls() > 0, true, "the clip holds them")
  act.clear_controls(clip.id, "cc", 1)
  local left = 0
  for _, c in ipairs(clip:controls()) do
    if c.type == "cc" then left = left + 1 end
  end
  eq(left, 0, "a kind is cleared")
end)

test("the record button arms the selected track, and stopping ends record mode", function()
  local _, b = song()
  api.engine_restart({ backend = "null", test_input = { frequency = 440, level = -12, channels = 2 } })
  act.select(b.id, 0)
  b.input = "1"
  act.record()
  eq(b.armed, true, "with no track armed, the selected one is")
  eq(paw.transport.recording, true, "recording is on")
  eq(paw.transport.playing, true, "and the transport plays")
  advance(400)
  act.record()
  eq(paw.transport.playing, false, "pressed again, it stops")
  eq(paw.transport.recording, false, "and record mode is over")
  T.until_recorded()
  eq(#b:clips(), 1, "leaving the take as a clip")
  paw.transport.record()
  advance(200)
  T.stop()
  eq(paw.transport.recording, false, "stopping any take ends record mode")
  paw.flush()
  api.engine_restart({ backend = "null" })
end)

test("a view paints in pixels for a graphical frontend, and gets the pointer", function()
  fresh()
  local seen = {}
  paw.ui.view("scope", {
    focusable = true,
    render = function() end,
    paint = function(self, g, ctx)
      g:rect(0, 0, ctx.width, ctx.height, { fill = "#101216" })
      g:text(10, 8, "hello", { color = "#ffffff", size = 14, bold = true })
      g:line(0, 30, ctx.width, 30, { color = "#343a47" })
      local part = g:sub(20, 40, 100, 50)
      part:rect(-10, -10, 200, 30, { fill = "#ff0000" })
      part:rect(500, 0, 10, 10, { fill = "#00ff00" })
      part:text(-30, 0, "hidden")
      part:poly({ -50, 25, 150, 25 }, { color = "#00ffff", width = 2 })
    end,
    pointer = function(self, e) seen[#seen + 1] = e.kind .. " " .. e.x .. "," .. e.y end,
  })
  T.fails(function() paw.canvas.open("arrange") end, "paints", "a view that does not paint")
  paw.canvas.open("scope", { title = "Scope", width = 320, height = 200 })
  local windows = paw.frontend.state(-1).modal.windows
  eq(#windows, 1, "the frontend is told which windows are open")
  eq(
    windows[1].name .. " " .. windows[1].title .. " " .. windows[1].width,
    "scope Scope 320",
    "with their titles and sizes"
  )
  eq(paw.ui.focused, "scope", "an opened window has the keyboard")

  local drawing = paw.canvas.paint("scope", 320, 200)
  eq(drawing.title, "Scope", "the drawing comes with the title")
  local ops = drawing.ops
  eq(#ops, 5, "what falls wholly outside a part is left out")
  eq(ops[1][1] .. " " .. ops[1][4] .. "x" .. ops[1][5], "r 320x200", "a rectangle")
  eq(ops[2][4], "hello", "text")
  eq(ops[3][2], "M 0.0 30.0 L 320.0 30.0", "a line, as a path")
  eq(
    table.concat({ ops[4][2], ops[4][3], ops[4][4], ops[4][5] }, " "),
    "20 40 100 20",
    "a rectangle is cut to the part it is drawn in"
  )
  eq(ops[5][2], "M 20.0 65.0 L 120.0 65.0", "and so is a line")

  paw.canvas.pointer("scope", { kind = "down", x = 12, y = 34, button = "left" })
  eq(seen[1], "down 12,34", "the view is handed the pointer")
  paw.ui.views:get("scope").paint = function() error("broken") end
  eq(
    paw.canvas.paint("scope", 100, 100).ops[2][4]:find("broken", 1, true) ~= nil,
    true,
    "a view that fails to paint says so in its window"
  )
  paw.canvas.close("scope")
  eq(#paw.frontend.state(-1).modal.windows, 0, "and a window is closed")
  eq(paw.ui.focused, "arrange", "giving the keyboard back")
end)

test("extensions add entries to the frontend's menus", function()
  fresh()
  local track = paw.add_track({ name = "Keys" })
  local clip = track:add_clip({ start = 4, length = 4 })
  local menus = paw.frontend.menus
  local seen = {}
  local before = { #menus.clip, #menus.timeline }
  table.insert(
    menus.clip,
    { label = "Count notes", only = "midi", run = function(id, beat) seen[#seen + 1] = id .. "@" .. beat end }
  )
  table.insert(menus.timeline, { label = "Mark here", command = "track.rename Marked" })
  local told = paw.frontend.state(-1).modal.menus
  eq(
    told.clip[#told.clip].label .. " " .. told.clip[#told.clip].only,
    "Count notes midi",
    "the frontend is told the entries"
  )
  eq(told.timeline[#told.timeline].label, "Mark here", "of each menu")

  paw.cursor.set_beat(0)
  paw.frontend.act.menu("clip", #menus.clip, clip.id, 5)
  eq(seen[1], clip.id .. "@5", "an entry's function gets the clip and the beat")
  eq(paw.cursor.beat, 5, "with the cursor put where the menu was opened")
  paw.frontend.act.menu("timeline", #menus.timeline, track.id, 2)
  eq(track.name, "Marked", "and a command line runs there")
  paw.frontend.act.menu("clip", 99, clip.id, 0)
  track.name = "Keys"
  paw.cursor.set_beat(6)
  paw.frontend.act.menu("timeline", #menus.timeline, -1, -1)
  eq(track.name .. " " .. paw.cursor.beat, "Marked 6", "from a button there is no place: the cursor stays")
  table.remove(menus.clip)
  table.remove(menus.timeline)
  eq(#menus.clip .. " " .. #menus.timeline, before[1] .. " " .. before[2], "the test leaves the menus as they were")
end)

test("a picker in a floating window takes clicks and the wheel", function()
  fresh()
  local chosen
  local items = {}
  for i = 1, 60 do
    items[i] = "item " .. i
  end
  paw.pick({ title = "Things", items = items, on_choose = function(item) chosen = item end })
  local float = paw.frontend.float(104, 40)
  local line
  for i, text in ipairs(float.lines) do
    if text:find("item 3", 1, true) and not line then line = i end
  end
  eq(line ~= nil, true, "the rows are drawn as lines")
  act.float_pointer("down", line, 5)
  eq(paw.pick.state().selected, 3, "a click on a row selects it")
  eq(chosen, nil, "and does not choose it")
  act.float_pointer("down", line, 5)
  eq(chosen, "item 3", "a second click, as in a double click, chooses it")
  paw.pick({ title = "Things", items = items, on_choose = function(item) chosen = item end })
  paw.frontend.float(104, 40)
  act.float_pointer("scroll_down", 3)
  eq(paw.pick.state().selected > 1, true, "the wheel moves down the list")
  act.float_pointer("down", 200)
  eq(paw.ui.float, nil, "a click outside closes it")
end)

-- Inputs and devices, chosen from menus the kernel fills.

local function with_test_input(fn)
  api.engine_restart({
    backend = "null",
    test_input = { frequency = 440, level = -12, channels = 2 },
    test_midi = { "Keys A" },
  })
  local ok, err = xpcall(fn, debug.traceback)
  api.engine_restart({ backend = "null" })
  if not ok then error(err, 0) end
end

local function labels(list)
  local out = {}
  for i, entry in ipairs(list) do
    out[i] = (entry.checked and "*" or "") .. entry.label
  end
  return table.concat(out, ", ")
end

test("a track's input is chosen from a menu: audio channels and pairs by device, MIDI ports, channels", function()
  with_test_input(function()
    local a = song()
    local menu = paw.frontend.input_menu(a.id)
    eq(
      labels(menu.audio),
      "*No audio input, test signal · 1, test signal · 2, test signal · 1/2",
      "each channel and each pair, named with the device"
    )
    eq(labels(menu.midi), "*All MIDI ports, Keys A", "every port, or one")
    eq(#menu.channel, 17, "every channel, or one of sixteen")
    act.choose_input(a.id, "audio", 4)
    eq(a.input, "1/2", "choosing a pair")
    eq(
      labels(paw.frontend.input_menu(a.id).audio):find("*test signal · 1/2", 1, true) ~= nil,
      true,
      "is shown as chosen"
    )
    eq(paw.frontend.state(-1).tracks[1].input_label, "test signal · 1/2", "and in the header")
    act.choose_input(a.id, "midi", 2)
    act.choose_input(a.id, "channel", 3)
    eq(a.input, nil, "a MIDI port takes the place of the audio input")
    eq(a.midi_input.port .. "/" .. a.midi_input.channel, "Keys A/2", "with the channel chosen")
    eq(paw.frontend.state(-1).tracks[1].input_label, "MIDI · Keys A · ch 2", "shown in words")
    act.choose_input(a.id, "midi", 1)
    act.choose_input(a.id, "channel", 1)
    eq(a.midi_input, nil, "back to every port and channel")
    act.toggle(a.id, "monitor")
    eq(a.monitor, true, "monitoring is a switch beside mute and solo")
  end)
end)

test("a choice that is saved but not there now is shown, and can be changed", function()
  local a = song()
  a.input = "3/4"
  a.midi_input = { port = "Gone keyboard" }
  local menu = paw.frontend.input_menu(a.id)
  eq(menu.audio[#menu.audio].checked, true, "the missing pair is listed as chosen")
  eq(menu.audio[#menu.audio].label:find("no such channel", 1, true) ~= nil, true, "and said to be missing")
  eq(labels(menu.midi):find("*Gone keyboard (not connected)", 1, true) ~= nil, true, "a port that is not connected too")
  act.choose_input(a.id, "audio", 1)
  eq(a.input, nil, "and none chosen instead")
end)

test("the audio devices are chosen from the engine's menu", function()
  with_test_input(function()
    song()
    local menu = paw.frontend.engine_menu()
    eq(
      menu.info[1].label:find("48 kHz", 1, true) ~= nil,
      true,
      "the sample rate and block size are shown: " .. menu.info[1].label
    )
    eq(
      labels(menu.input):find("*test signal  (2 ch)", 1, true) ~= nil,
      true,
      "the input open, with its channels: " .. labels(menu.input)
    )
    eq(#menu.block, 8, "the device's own block size, or one of seven")
    act.choose_engine("block", 4)
    eq(api.engine_get().buffer_size, 128, "a block size is chosen")
    eq(labels(paw.frontend.engine_menu().block):find("*128 frames", 1, true) ~= nil, true, "and shown as chosen")
    eq(paw.frontend.state(-1).project.engine, "null · 48 kHz", "the indicator in the transport bar")
  end)
end)

test("notes are drawn, chosen with clicks and a box, and moved and stretched together", function()
  fresh()
  local track = paw.add_track({ name = "Keys" })
  track:add_device("synth")
  local clip = track:add_clip({
    start = 0,
    length = 8,
    notes = {
      { pitch = 60, start = 0, length = 1 },
      { pitch = 64, start = 1, length = 1 },
      { pitch = 67, start = 2, length = 1 },
      { pitch = 72, start = 4, length = 2 },
    },
  })
  local act, id = paw.frontend.act, clip.id
  local function chosen() return table.concat(paw.frontend.chosen_notes(id), " ") end
  local function notes()
    local out = {}
    for i, n in ipairs(clip:notes()) do
      out[i] = n.pitch .. "@" .. n.start .. "+" .. n.length
    end
    return table.concat(out, " ")
  end
  paw.ui.views:get("pianoroll"):edit(clip)

  -- A drawn note is the one chosen note.
  local at = act.add_note(id, 62, 3.1, 0.6)
  eq(notes():find("62@3+0.5", 1, true) ~= nil, true, "a drawn note lands on the grid")
  eq(chosen(), tostring(at), "and is the one chosen")
  act.add_note(id, 61, 3.1, 0.3, true)
  eq(notes():find("61@3.1+0.3", 1, true) ~= nil, true, "with Shift it stays where it was drawn")
  act.remove_note(id, (select(2, clip:note_at(61, 3.1))))
  act.remove_note(id, (select(2, clip:note_at(62, 3))))
  eq(notes(), "60@0+1 64@1+1 67@2+1 72@4+2", "a note is taken away")

  -- Clicks.
  act.select_note(id, 2, "only")
  eq(chosen(), "2", "a click chooses the note alone")
  act.select_note(id, 3, "toggle")
  eq(chosen(), "2 3", "Shift click adds one")
  act.select_note(id, 2, "toggle")
  eq(chosen(), "3", "or takes it out")
  eq(paw.frontend.chosen_notes(clip.id)[1], 3, "the chosen, which the roll draws lit in both frontends")

  -- A box.
  eq(act.select_notes_box(id, 0.5, 59, 2.5, 66, "only"), 2, "a box takes the notes it touches")
  eq(chosen(), "1 2", "by time and pitch")
  act.select_notes_box(id, 3.5, 70, 5, 75, "add")
  eq(chosen(), "1 2 4", "Shift adds another box's notes")
  act.select_notes_box(id, 0, 0, 0, 0, "only")
  eq(chosen(), "", "a box on nothing lets go of them")

  -- Moving together: the grabbed note lands on the grid, the rest keep their distance.
  act.select_notes_box(id, 0, 59, 2.9, 68, "only")
  eq(chosen(), "1 2 3", "three notes chosen")
  api.undo_checkpoint()
  act.drag_notes(id, 2, 0.6, 2, false, false)
  api.undo_checkpoint()
  eq(notes(), "62@0.5+1 66@1.5+1 69@2.5+1 72@4+2", "the chosen notes move as one, in time and pitch")
  eq(chosen(), "1 2 3", "and stay chosen")
  paw.undo()
  eq(notes(), "60@0+1 64@1+1 67@2+1 72@4+2", "as one undo step")
  eq(chosen(), "", "an edit made another way lets go of them")
  -- A note that is not among the chosen goes alone.
  act.select_note(id, 1, "only")
  act.drag_notes(id, 4, 1, 0, false, false)
  eq(notes(), "60@0+1 64@1+1 67@2+1 72@5+2", "a note that was not chosen moves alone")
  eq(chosen(), "4", "and is then the chosen one")
  -- A copy.
  act.drag_notes(id, 4, -2, -12, true, false)
  eq(notes(), "60@0+1 64@1+1 67@2+1 60@3+2 72@5+2", "with Ctrl a copy is dropped")
  eq(chosen(), "4", "and the copy is the one chosen")
  act.remove_note(id, 4)
  -- Nothing leaves the clip.
  act.select_all_notes(id)
  act.drag_notes(id, 1, -5, 0, false, false)
  eq(notes(), "60@0+1 64@1+1 67@2+1 72@5+2", "a drag stops at the start of the clip")

  -- Stretching both ends.
  act.select_notes_box(id, 0, 59, 1.9, 66, "only")
  act.stretch_notes(id, 2, 0, 0.5, false)
  eq(notes(), "60@0+1.5 64@1+1.5 67@2+1 72@5+2", "the right ends of the chosen notes move together")
  act.stretch_notes(id, 2, 0.5, 0, false)
  eq(notes(), "60@0.5+1 64@1.5+1 67@2+1 72@5+2", "and the left ends, the right ones staying")
  act.stretch_notes(id, 2, 5, 0, false)
  eq(notes(), "60@1.25+0.25 67@2+1 64@2.25+0.25 72@5+2", "a note is never shorter than a grid step")

  -- Velocity of the chosen, and the keys.
  act.set_velocity(id, 1, 40)
  local v = {}
  for i, n in ipairs(clip:notes()) do
    v[i] = n.velocity
  end
  eq(table.concat(v, " "), "40 100 40 100", "a velocity set on a chosen note goes to all of them")
  paw.keymap.feed("x")
  eq(notes(), "67@2+1 72@5+2", "x takes the chosen notes away")
  paw.keymap.feed("gA")
  eq(chosen(), "1 2", "gA chooses every note")
  paw.keymap.feed("<C-a>")
  eq(notes(), "68@2+1 73@5+2", "Ctrl-a moves the chosen notes up a semitone")
  paw.keymap.feed("<Esc>")
  eq(chosen() .. " " .. paw.ui.focused, " pianoroll", "Esc lets go of them first")
  paw.keymap.feed("<Esc>")
  eq(paw.ui.focused, "pianoroll", "and then stays in the roll, as Escape does in every view")
end)

-- Clips chosen with the pointer.

--- Three tracks with clips at beats 0, 4, 8 and 12 each, named by track and place.
local function grid_song()
  fresh()
  paw.opt.grid = 1
  local tracks, clips = {}, {}
  for t = 1, 3 do
    tracks[t] = paw.add_track({ name = "t" .. t })
    for i = 0, 3 do
      local c = tracks[t]:add_clip({
        start = i * 4,
        length = 2,
        name = t .. "." .. (i + 1),
        notes = { { pitch = 60, start = 0, length = 1 } },
      })
      clips[t .. "." .. (i + 1)] = c.id
    end
  end
  paw.flush()
  local names = {}
  for name, id in pairs(clips) do
    names[id] = name
  end
  local function chosen()
    local out = {}
    for i, id in ipairs(paw.frontend.chosen_clips()) do
      out[i] = names[id]
    end
    table.sort(out)
    return table.concat(out, " ")
  end
  return tracks, clips, chosen
end

test("clips are chosen with clicks, Ctrl, Shift and a box", function()
  local tracks, c, chosen = grid_song()
  act.select_clip(c["1.2"], 4.5)
  eq(chosen(), "1.2", "a click chooses the clip alone")
  eq(paw.keymap.mode, "n", "and stays in normal mode")
  local state = paw.frontend.state(-1)
  local flags = 0
  for _, clip in ipairs(state.clips) do
    if clip.selected then
      flags = flags + 1
      eq(clip.id, c["1.2"], "the frontend is told which clip")
    end
  end
  eq(flags, 1, "one clip is drawn chosen")
  act.select_clip(c["2.3"], 8, "toggle")
  eq(chosen(), "1.2 2.3", "Ctrl and a click adds one")
  eq(paw.keymap.mode .. " " .. paw.keymap.visual.kind, "x clips", "and the chosen clips are visual mode's selection")
  eq(paw.frontend.state(-1).modal.selection.kind, "clips", "which the frontend is told")
  eq(type(paw.json.encode(paw.frontend.state(-1))), "string", "in a form it can be sent in")
  act.select_clip(c["1.2"], 4, "toggle")
  eq(chosen(), "2.3", "or takes one out")
  act.select_clip(c["2.1"], 0, "only")
  act.select_clip(c["2.4"], 12, "add")
  eq(chosen(), "2.1 2.2 2.3 2.4", "Shift and a click takes in the clips between on the same track")
  act.select_clip(c["1.2"], 4, "only")
  act.select_clip(c["3.3"], 8, "add")
  eq(chosen(), "1.2 1.3 2.2 2.3 3.2 3.3", "across tracks the rectangle the two span")
  act.select(tracks[1].id, 14.5)
  eq(chosen(), "", "a click on an empty lane lets go of them")
  eq(paw.keymap.mode, "n", "and of the selection")

  eq(act.select_clips_box(1, 3, 2, 9, "only"), 4, "a box chooses the clips it touches")
  eq(chosen(), "1.2 1.3 2.2 2.3", "on the rows and the stretch it covers")
  act.select_clips_box(3, 0, 3, 1, "add")
  eq(chosen(), "1.2 1.3 2.2 2.3 3.1", "Shift adds another box's clips")
  act.select_clips_box(1, 3, 1, 9, "toggle")
  eq(chosen(), "2.2 2.3 3.1", "Ctrl turns them over")
  paw.keymap.feed("<Esc>")
  eq(chosen(), "", "Esc lets go of them")
end)

test("the keys act on the chosen clips", function()
  local tracks, c, chosen = grid_song()
  act.select_clips_box(1, 3, 2, 9, "only")
  paw.keymap.feed("y")
  local reg = paw.keymap.getreg()
  eq(
    reg.kind .. " " .. #reg.rows .. " " .. #reg.rows[1] .. " " .. reg.length,
    "range 2 2 6",
    "y yanks the chosen clips, whole"
  )
  act.select_clip(c["1.1"], 0, "only")
  act.select_clip(c["3.4"], 12, "toggle")
  paw.keymap.feed("d")
  eq(
    #tracks[1]:clips() .. " " .. #tracks[3]:clips() .. " " .. #tracks[2]:clips(),
    "3 3 4",
    "d deletes them and nothing between"
  )
  eq(chosen(), "", "and lets go of them")
  paw.cursor.set_track(tracks[1])
  paw.cursor.set_beat(20)
  paw.keymap.feed("P")
  eq(#tracks[1]:clips() .. " " .. #tracks[3]:clips(), "4 4", "they paste at the cursor, two tracks apart")
  eq(tracks[3]:clips()[4].start, 32, "as far apart as they were")
  act.select_clip(c["2.2"], 4, "only")
  act.select_clip(c["2.3"], 8, "toggle")
  paw.keymap.feed("x")
  eq(#tracks[2]:clips(), 2, "x deletes the chosen clips too")
  act.select_clip(c["1.2"], 4.4, "only")
  paw.keymap.feed("l")
  eq(chosen(), "1.2", "one clip chosen stays chosen while the cursor is in it")
  paw.keymap.feed("w")
  eq(chosen(), "", "and is let go of when the cursor leaves it")
end)

test("chosen clips move and copy together, by whole grid steps, as one undo step", function()
  local _, c, chosen = grid_song()
  local function at(name)
    local clip = paw.clip(c[name])
    return clip:track().name .. "@" .. clip.start
  end
  act.select_clip(c["1.2"], 4, "only")
  act.select_clip(c["2.3"], 8, "toggle")
  api.undo_checkpoint()
  act.drag_clips(c["1.2"], 2.4, 1, false, false)
  api.undo_checkpoint()
  eq(at("1.2") .. " " .. at("2.3"), "t2@6 t3@10", "dragging one chosen clip moves them all, across tracks")
  eq(chosen(), "1.2 2.3", "and they stay chosen")
  paw.undo()
  eq(at("1.2") .. " " .. at("2.3"), "t1@4 t2@8", "as one undo step")

  -- Relative snapping.
  paw.clip(c["1.2"]).start = 4.5
  act.select_clip(c["1.2"], 4.5, "only")
  act.drag_clips(c["1.2"], 1.3, 0, false, false)
  eq(at("1.2"), "t1@5.5", "a clip off the grid moves by whole steps and keeps its offset")
  act.drag_clips(c["1.2"], 0.3, 0, false, true)
  near(paw.clip(c["1.2"]).start, 5.8, 1e-9, "Shift moves it freely")
  paw.clip(c["1.2"]).start = 4

  -- Limits.
  act.select_clip(c["1.1"], 0, "only")
  act.select_clip(c["3.1"], 0, "toggle")
  act.drag_clips(c["3.1"], -3, 5, false, false)
  eq(at("1.1") .. " " .. at("3.1"), "t1@0 t3@0", "nothing goes before the start or off the tracks")
  act.drag_clips(c["3.1"], 0, -2, false, false)
  eq(at("1.1") .. " " .. at("3.1"), "t1@0 t3@0", "nor above the first track, together")

  -- Copies.
  act.select_clip(c["2.2"], 4, "only")
  act.select_clip(c["2.3"], 8, "toggle")
  local made = act.drag_clips(c["2.2"], 12, 1, true, false)
  eq(at("2.2") .. " " .. at("2.3"), "t2@4 t2@8", "with Ctrl the clips stay")
  eq(
    #made .. " " .. paw.clip(made[1]):track().name .. "@" .. paw.clip(made[1]).start .. " " .. paw.clip(made[2]).start,
    "2 t3@16 20",
    "and copies are dropped"
  )
  eq(#paw.clip(made[1]):notes(), 1, "with their notes")
  eq(table.concat(paw.frontend.chosen_clips(), " "), made[1] .. " " .. made[2], "the copies are then the chosen ones")

  -- A clip that is not chosen goes alone.
  act.drag_clips(c["1.4"], 4, 0, false, false)
  eq(at("1.4") .. " " .. chosen(), "t1@16 1.4", "a clip that was not chosen moves alone, and is then chosen")
end)

test("either edge of chosen clips is trimmed, hiding notes, and Alt slips what plays", function()
  local tracks, c = grid_song()
  local clip = paw.clip(c["1.2"])
  clip:add_note({ pitch = 64, start = 1.5, length = 0.5 })
  local function notes()
    local out = {}
    for i, n in ipairs(clip:notes()) do
      out[i] = n.pitch .. "@" .. n.start
    end
    return table.concat(out, " ")
  end
  local function place(id)
    local x = paw.clip(id)
    return x.start .. "+" .. x.length
  end
  act.select_clip(c["1.2"], 4, "only")
  api.undo_checkpoint()
  act.trim_clips(c["1.2"], "start", 1.2, false, false)
  api.undo_checkpoint()
  eq(place(c["1.2"]), "5+1", "the start is trimmed to the grid, the end staying")
  eq(notes(), "60@-1 64@0.5", "the notes stay where they were in time")
  eq(#paw.frontend.preview(clip.id), 3, "the note before the new start is hidden")
  paw.undo()
  eq(place(c["1.2"]) .. " " .. notes(), "4+2 60@0 64@1.5", "as one undo step")
  act.trim_clips(c["1.2"], "start", 1, false, false)
  act.trim_clips(c["1.2"], "start", -3, false, false)
  eq(
    place(c["1.2"]) .. " " .. notes(),
    "2+4 60@2 64@3.5",
    "dragged out again the hidden note comes back, and the clip reaches further"
  )
  act.trim_clips(c["1.2"], "start", 9, false, false)
  eq(place(c["1.2"]), "5+1", "never shorter than a grid step")
  paw.ui.views:get("pianoroll"):edit(paw.clip(clip.id))
  local shown = T.roll_notes()
  eq(
    #shown .. " " .. shown[1].hit.place .. " " .. shown[1].props.label,
    "1 2 E4",
    "the piano roll does not show the hidden note, and names the other by its place"
  )
  paw.ui.hide("pianoroll")
  paw.ui.focus("arrange")
  act.select_all_notes(clip.id)
  eq(table.concat(paw.frontend.chosen_notes(clip.id), " "), "2", "nor can it be chosen")

  -- Several, and the right edge.
  act.select_clip(c["2.2"], 4, "toggle")
  act.trim_clips(c["2.2"], "end", 1.4, false, false)
  eq(place(c["1.2"]) .. " " .. place(c["2.2"]), "5+2 4+3", "the same edge of every chosen clip moves by as much")
  act.trim_clips(c["2.2"], "start", 0.3, true, false)
  near(paw.clip(c["2.2"]).start, 4.3, 1e-9, "Shift trims off the grid")

  -- Slip.
  act.select_clip(c["1.3"], 8, "only")
  act.trim_clips(c["1.3"], "start", 0.5, false, true)
  eq(
    place(c["1.3"]) .. " " .. paw.clip(c["1.3"]):notes()[1].start,
    "8+2 0.5",
    "Alt moves what plays inside, the edges staying"
  )

  -- Audio: the clip starts further into its file.
  local samples = {}
  for i = 1, 48000 * 4 do
    samples[i] = 0.25
  end
  local file = T.write_wav(T.scratch .. "/trim.wav", samples)
  local audio = tracks[3]:add_clip({ file = file, start = 20, length = 4 })
  audio.fade_in = 1
  act.select_clip(audio.id, 20, "only")
  act.trim_clips(audio.id, "start", 1, false, false)
  local a = audio:get()
  near(a.offset, paw.time.seconds(1), 1e-9, "a trimmed audio clip plays from further into its file")
  eq(a.start .. "+" .. a.length, "21+3", "from its new start")
  act.trim_clips(audio.id, "start", -3, false, false)
  a = audio:get()
  eq(a.start .. " " .. a.offset, "20 0", "and reaches back no further than the file's start")
  act.trim_clips(audio.id, "start", -1, false, true)
  near(audio:get().offset, paw.time.seconds(1), 1e-9, "Alt slips the sound inside the clip")
  eq(audio:get().start, 20, "where the clip is")

  -- Fades and gain, from the handles.
  local other = tracks[3]:add_clip({ file = file, start = 30, length = 2 })
  act.select_clip(audio.id, 20, "only")
  act.select_clip(other.id, 30, "toggle")
  act.set_fade(audio.id, "in", 1.5)
  act.set_fade(audio.id, "out", 9)
  eq(
    audio.fade_in .. " " .. audio.fade_out .. " " .. other.fade_in .. " " .. other.fade_out,
    "1.5 4 1.5 2",
    "a corner handle sets the fade of the chosen audio clips, each no longer than the clip"
  )
  act.set_clip_gain(audio.id, -6)
  eq(audio:get().gain .. " " .. other:get().gain, "-6 -6", "the top line sets their gain")
  act.set_clip_gain(audio.id, -100)
  eq(audio:get().gain, -60, "down to -60 dB")
  local told
  for _, clip in ipairs(paw.frontend.state(-1).clips) do
    if clip.id == audio.id then told = clip end
  end
  eq(told.fade_in .. " " .. told.gain, "1.5 -60", "the frontend is told the fades and the gain")
end)

test("a track's height is its own, flags are swept, and headers are dragged into and out of groups", function()
  fresh()
  local a, b, c, d =
    paw.add_track({ name = "a" }),
    paw.add_track({ name = "b" }),
    paw.add_track({ name = "c" }),
    paw.add_track({ name = "d" })
  paw.flush()
  local function heights()
    local out = {}
    for i, t in ipairs(paw.frontend.state(-1).tracks) do
      out[i] = t.height
    end
    return table.concat(out, " ")
  end
  eq(heights(), "1 1 1 1 1", "every track is as tall as the zoom makes them")
  act.set_track_height(b.id, 2.5)
  eq(heights(), "1 2.5 1 1 1", "a track's bottom edge dragged makes it taller")
  eq(b:get().height, 2.5, "kept with the track")
  local snap = b:snapshot()
  eq(snap.height, 2.5, "and copied with it")
  act.set_track_height(b.id, 0.01)
  eq(b:get().height, 0.25, "never too short to see")
  act.set_track_height(b.id, 1)
  eq(b:get().height, nil, "back to the zoom's height, nothing is kept")

  -- Sweeping across M, S and R.
  act.set_flag(a.id, "mute", true)
  act.set_flag(b.id, "mute", true)
  act.set_flag(c.id, "mute", true)
  eq(
    tostring(a.mute) .. tostring(b.mute) .. tostring(c.mute) .. tostring(d.mute),
    "truetruetruefalse",
    "a sweep sets each flag it crosses as the first was set"
  )
  act.set_flag(b.id, "armed", true)
  eq(b.armed, true, "arm too")
  act.sweep_flag(3, 1, "solo", true)
  eq(
    tostring(a.solo) .. tostring(b.solo) .. tostring(c.solo) .. tostring(d.solo),
    "truetruetruefalse",
    "a sweep upwards over three rows"
  )
  T.fails(function() act.set_flag(a.id, "volume", true) end, "flag", "only flags")

  -- Groups.
  local g = paw.groups.make({ b, c }, "G")
  local function order()
    local out = {}
    for i, id in ipairs(paw.groups.rows()) do
      local t = paw.track(id)
      out[i] = t.name .. (paw.groups.of(id) and "<" .. paw.track(paw.groups.of(id)).name or "")
    end
    return table.concat(out, " ")
  end
  eq(order(), "a G b<G c<G d", "a group and its members")
  act.move_track(d.id, 3)
  eq(order(), "a G d<G b<G c<G", "a header dragged in among a group's tracks goes into the group")
  act.move_track(d.id, 1)
  eq(order(), "d a G b<G c<G", "and dragged out of them, out of the group")
  act.move_track(a.id, 3)
  eq(order(), "d G a<G b<G c<G", "dropped right under a group's own header, into it")
  act.move_track(g.id, 1)
  eq(order(), "G a<G b<G c<G d", "a group takes its tracks along")
end)

test("the chosen clips are split at the edit cursor and glued", function()
  local tracks, c = grid_song()
  paw.clip(c["2.2"]).length = 4
  act.select_clip(c["1.2"], 4, "only")
  act.select_clip(c["2.2"], 4, "toggle")
  paw.cursor.set_beat(5)
  paw.keymap.feed("S")
  local function starts(t)
    local out = {}
    for i, clip in ipairs(tracks[t]:clips()) do
      out[i] = clip.start .. "+" .. clip.length
    end
    return table.concat(out, " ")
  end
  eq(
    starts(1) .. " | " .. starts(2),
    "0+2 4+1 5+1 8+2 12+2 | 0+2 4+1 5+3 8+2 12+2",
    "S splits every chosen clip at the cursor"
  )
  eq(#paw.frontend.chosen_clips(), 4, "and both halves are chosen")
  act.clear_clip_selection()
  paw.cursor.set_track(tracks[3])
  paw.cursor.set_beat(9)
  paw.keymap.feed("S")
  eq(starts(3), "0+2 4+2 8+1 9+1 12+2", "with none chosen, the clip under the cursor")

  act.select_clip(c["1.3"], 8, "only")
  act.select_clip(c["1.4"], 12, "toggle")
  act.select_clip(c["3.1"], 0, "toggle")
  act.glue_clips()
  eq(starts(1), "0+2 4+1 5+1 8+6", "glue makes one clip of the chosen clips on a track, the gap with them")
  eq(#paw.clip(c["1.3"]):notes(), 2, "with all their notes")
  eq(starts(3), "0+2 4+2 8+1 9+1 12+2", "one clip alone on its track stays as it is")

  -- Audio clips are glued into a new file.
  local samples = {}
  for i = 1, 48000 do
    samples[i] = 0.25
  end
  local file = T.write_wav(T.scratch .. "/glue.wav", samples)
  local a1 = tracks[2]:add_clip({ file = file, start = 20, length = 1 })
  local a2 = tracks[2]:add_clip({ file = file, start = 21, length = 1 })
  act.select_clip(a1.id, 20, "only")
  act.select_clip(a2.id, 21, "toggle")
  act.glue_clips()
  local audio = {}
  for _, clip in ipairs(tracks[2]:clips()) do
    if clip.kind == "audio" then audio[#audio + 1] = clip.start .. "+" .. clip.length end
  end
  eq(table.concat(audio, " "), "20+2", "chosen audio clips are glued into one")

  -- A glue of audio clips that fails says why.
  local glue = paw.media.glue
  paw.media.glue = function() error("the disk is full", 0) end
  T.after(function() paw.media.glue = glue end)
  local b1 = tracks[2]:add_clip({ file = file, start = 24, length = 1 })
  local b2 = tracks[2]:add_clip({ file = file, start = 25, length = 1 })
  act.select_clip(b1.id, 24, "only")
  act.select_clip(b2.id, 25, "toggle")
  act.glue_clips()
  paw.media.glue = glue
  eq(paw.ui.message.text, "the disk is full", "the message gives the error")
end)

test("the piano roll's other gestures: erase, keyboard ranges, velocity strokes, note length, snap", function()
  fresh()
  local track = paw.add_track({ name = "Keys" })
  track:add_device("synth")
  local clip = track:add_clip({
    start = 4,
    length = 8,
    notes = {
      { pitch = 60, start = 0, length = 1, velocity = 100 },
      { pitch = 64, start = 1, length = 1, velocity = 100 },
      { pitch = 67, start = 2, length = 1, velocity = 100 },
      { pitch = 72, start = 4, length = 2, velocity = 100 },
    },
  })
  local act, id = paw.frontend.act, clip.id
  local function chosen() return table.concat(paw.frontend.chosen_notes(id), " ") end
  local function notes()
    local out = {}
    for i, n in ipairs(clip:notes()) do
      out[i] = n.pitch .. "@" .. n.start .. "+" .. n.length
    end
    return table.concat(out, " ")
  end
  local function velocities()
    local out = {}
    for i, n in ipairs(clip:notes()) do
      out[i] = n.velocity
    end
    return table.concat(out, " ")
  end
  paw.ui.views:get("pianoroll"):edit(clip)

  -- Alt and a drag: every note crossed goes, even between two points far apart.
  api.undo_checkpoint()
  eq(act.erase_notes(id, { { 0.5, 60 }, { 2.5, 67 } }), 3, "a stroke from the first note to the third crosses three")
  api.undo_checkpoint()
  eq(notes(), "72@4+2", "they are taken away")
  paw.undo()
  eq(notes(), "60@0+1 64@1+1 67@2+1 72@4+2", "as one undo step")
  eq(act.erase_notes(id, { { 3, 60 }, { 3.5, 60 } }), 0, "a stroke over nothing takes nothing")

  -- The keyboard: a right drag over keys chooses those pitches.
  eq(act.select_pitches(id, 66, 61, "only"), 1, "the notes from C#4 to F#4, whichever way the drag went")
  eq(chosen(), "2", "only the note in that range")
  act.select_pitches(id, 59, 61, "add")
  eq(chosen(), "1 2", "with Shift another range is added")
  -- A box with Ctrl toggles what it touches.
  act.select_notes_box(id, 0, 59, 2.5, 70, "toggle")
  eq(chosen(), "3", "Ctrl and a box toggle the notes it touches")

  -- Velocity strokes: only the chosen notes, if any are chosen.
  act.draw_velocities(id, { { 0, 0.5 }, { 3, 0.5 } }, 0)
  eq(velocities(), "100 100 64 100", "with a note chosen only it takes the stroke")
  act.clear_note_selection()
  act.draw_velocities(id, { { 0, 0 }, { 4, 1 } }, 0)
  eq(velocities(), "1 32 64 127", "without, each note under the stroke takes its height there")
  act.draw_velocities(id, { { 1.05, 0.75 } }, 0.1)
  eq(velocities(), "1 95 64 127", "a click sets the one note starting within reach")

  -- The note length: a click gives it; a drawn note sets it.
  act.set_note_length(1)
  local at = act.add_note(id, 50, 6, 0)
  eq(clip:notes()[at].length, 1, "a click gives the roll's note length")
  at = act.add_note(id, 51, 6, 0.5)
  eq(clip:notes()[at].length, 0.5, "a drawn note is as long as it was drawn")
  eq(paw.ui.views:get("pianoroll"):step_length(), 0.5, "and its length becomes the note length")
  at = act.add_note(id, 52, 6, 0)
  eq(clip:notes()[at].length, 0.5, "which the next click gives")
  act.set_note_length(0)
  eq(paw.ui.views:get("pianoroll"):step_length(), paw.opt.note_grid, "0 means one grid step")

  -- Snap off: everything lands where the pointer let go.
  paw.opt.note_snap = false
  at = act.add_note(id, 53, 6.1, 0.3)
  eq(clip:notes()[at].start .. "+" .. clip:notes()[at].length, "6.1+0.3", "with snap off a note is drawn where it was")
  act.drag_notes(id, at, 0.07, 0, false, false)
  eq(select(2, clip:note_at(53, 6.17)) ~= nil, true, "and moved off the grid")
  paw.opt.note_snap = true
  eq(paw.opt.note_snap, true, "notes snap again")

  act.toggle_note_snap()
  eq(paw.opt.note_snap, false, "the snap button turns snap off")
  act.toggle_note_snap()
  eq(paw.opt.note_snap, true, "and on")

  -- Quantize: the chosen notes, or all.
  local q = track:add_clip({
    start = 20,
    length = 4,
    notes = {
      { pitch = 60, start = 0.1, length = 0.5 },
      { pitch = 62, start = 1.2, length = 0.5 },
      { pitch = 64, start = 3.9, length = 0.5 },
    },
  })
  local function starts()
    local out = {}
    for i, n in ipairs(q:notes()) do
      out[i] = n.start .. "+" .. n.length
    end
    return table.concat(out, " ")
  end
  act.select_note(q.id, 2, "only")
  eq(act.quantize_notes(q.id), 1, "with a note chosen only it is quantized")
  eq(starts(), "0.1+0.5 1.25+0.5 3.9+0.5", "to the nearest grid step, keeping its length")
  eq(paw.frontend.chosen_notes(q.id)[1], 2, "and it stays chosen")
  eq(paw.frontend.chosen_text(q.id), "1 note · 6.2.25 – 6.2.75", "the toolbar is told how many are chosen and where")
  act.clear_note_selection()
  paw.opt.note_grid = 0.5
  act.quantize_notes(q.id)
  eq(starts(), "0+0.5 1.5+0.5 3.5+0.5", "with none chosen all are, and none leaves the clip")
  paw.opt.note_grid = 0.25
  paw.ui.views:get("pianoroll"):edit(q)
  paw.commands.exec("notes.quantize 50")
  eq(starts(), "0+0.5 1.5+0.5 3.5+0.5", "the command does the same, at a strength")

  -- The other clips of the track show faintly where they overlap this one.
  local other = track:add_clip({
    start = 22,
    length = 4,
    notes = { { pitch = 70, start = 0, length = 1 }, { pitch = 71, start = 3, length = 1 } },
  })
  local ghosts = paw.roll_clips.context()
  eq(#ghosts, 1, "only the notes that sound during this clip")
  eq(ghosts[1].pitch .. "@" .. ghosts[1].start, "70@2", "placed in this clip's beats")
  other:remove()
  act.set_note_length(0)

  -- A click on the roll's ruler moves the playhead within the clip.
  paw.ui.views:get("pianoroll"):edit(clip)
  act.roll_seek(id, 2)
  eq(api.transport_get().position, 6, "the playhead goes to that beat of the clip")
end)

test("an audio clip's start is trimmed by the tempo map where it is", function()
  fresh()
  paw.opt.grid = 1
  paw.project.tempo = 120
  paw.tempo.set(8, 60)
  local samples = {}
  for i = 1, 48000 * 8 do
    samples[i] = 0.25
  end
  local file = T.write_wav(T.scratch .. "/map.wav", samples)
  local track = paw.add_track({ name = "a" })
  local clip = track:add_clip({ file = file, start = 10, length = 4 })
  paw.flush()
  act.select_clip(clip.id, 10, "only")
  act.trim_clips(clip.id, "start", 1, false, false)
  near(clip:get().offset, 1, 1e-6, "a beat at 60 bpm is a second into the file")
  act.trim_clips(clip.id, "start", -5, false, false)
  eq(clip:get().start, 10, "and the start goes back no further than the file's")
  near(clip:get().offset, 0, 1e-6, "which is where it began")
end)

test("a track's output and sends are shown and changed", function()
  fresh()
  local a = paw.add_track({ name = "Guitar" })
  local bus = paw.add_track({ name = "Bus" })
  local verb = paw.add_track({ name = "Reverb" })
  local act = paw.frontend.act
  local r = paw.frontend.routing(a.id)
  eq(
    r.output .. " " .. #r.targets .. " " .. r.targets[1].name,
    "Master 3 Master",
    "a track plays into the master, and may play into the others"
  )
  act.set_output(a.id, bus.id)
  eq(paw.frontend.routing(a.id).output, "Bus", "its output is another track")
  local names = {}
  for i, t in ipairs(paw.frontend.routing(bus.id).targets) do
    names[i] = t.name
  end
  eq(table.concat(names, " "), "Master Reverb", "a track that plays into this one is not offered as its output")
  act.set_output(a.id, 0)
  eq(a.output, nil, "and the master again")

  act.add_send(a.id, verb.id, -9)
  act.add_send(a.id, verb.id, -3)
  local sends = paw.frontend.routing(a.id).sends
  eq(
    #sends .. " " .. sends[1].name .. " " .. sends[1].level .. " " .. tostring(sends[1].pre),
    "1 Reverb -9 false",
    "a send has a target and a level, once"
  )
  act.set_send(a.id, 1, -20)
  act.set_send(a.id, 1, nil, true)
  sends = paw.frontend.routing(a.id).sends
  eq(
    sends[1].level .. " " .. tostring(sends[1].pre),
    "-20 true",
    "its level and whether it is ahead of the fader are changed apart"
  )
  paw.cursor.set_track(a)
  eq(paw.frontend.state(-1).routing.sends[1].name, "Reverb", "the frontend is told the selected track's routing")
  act.remove_send(a.id, 1)
  eq(#a.sends, 0, "a send is taken away")

  -- The same from commands.
  paw.cmd("send", { "rev", -6 })
  eq(a.sends[1].target .. " " .. a.sends[1].level, verb.id .. " -6", "send takes part of a name and a level")
  paw.cmd("send.remove", { "Reverb" })
  eq(#a.sends, 0, "send.remove takes it away")
  paw.cmd("track.output", { "Bus" })
  eq(a.output, bus.id, "track.output names the track to play into")
  paw.cmd("track.output", { "master" })
  eq(a.output, nil, "or the master")
end)

test("a click on a mixer strip's insert picks that device in the device panel", function()
  local a, b = song()
  a:add_device("delay")
  paw.cursor.set_track(b)
  act.pick_device(a.id, 2)
  eq(paw.cursor.track_id(), a.id, "the strip's track is the cursor's")
  eq(paw.ui.focused, "devices", "the device panel has the keyboard")
  local state = paw.frontend.state(-1)
  eq(state.modal.device, 2, "on the second device")
  eq(state.modal.param, 0, "on its own line")
end)
