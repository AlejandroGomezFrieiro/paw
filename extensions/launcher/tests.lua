-- Tests of the clip launcher extension: clips in slots, launched on their
-- boundary, scenes, stopping, going back to the timeline, saving, undo,
-- controllers, the session view, and a performance captured into the
-- timeline and rendered. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, near, fails, fresh, render = T.test, T.eq, T.near, T.fails, T.fresh, T.render
local api = paw.api
local launcher

local function start()
  if not paw.ext.loaded.launcher then paw.ext.load("extensions/launcher") end
  launcher = require("launcher")
  fresh()
  api.engine_restart({})
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
end

local until_ = T.until_

--- A synth track with a clip of one long note in a slot.
local function synth(name, row, pitch, bars)
  local t = paw.add_track({ name = name })
  t:add_device("synth", { attack = 0.001, release = 0.01 })
  local length = 4 * (bars or 1)
  local id =
    launcher.add(t.id, row, { length = length, notes = { { pitch = pitch or 57, start = 0, length = length } } })
  return t, id
end

local function state(track) return launcher.state()[track] or {} end

--- The first frame of a 16-bit WAV written by `paw.render` that is not silent.
local function first_sound(info)
  local data = T.read_file(info.path)
  local at = data:find("data", 1, true) + 8
  for i = at, #data - 1, 2 do
    local lo, hi = data:byte(i, i + 1)
    if lo ~= 0 or hi ~= 0 then return math.floor((i - at) / 4) end
  end
  return -1
end

-- The model ------------------------------------------------------------------

test("launcher: a clip in a slot is a clip off the timeline, its row in its meta, edited like any clip", function()
  start()
  local t = paw.add_track({ name = "Keys" })
  local id = launcher.add(t.id, 2, { start = 8, length = 2, notes = { { pitch = 60, start = 0, length = 1 } } })
  eq(#api.clip_list(t.id), 0, "nothing on the timeline")
  local cues = api.cue_list(t.id)
  eq(#cues, 1, "one clip off the timeline")
  eq(cues[1].cue, true, "a cue clip")
  eq(cues[1].meta.launcher.row, 2, "its row in its meta")
  eq(cues[1].start, 0, "starting at 0 whatever was asked")
  eq(launcher.clip(t.id, 2).id, id, "in its slot")
  paw.clip(id):set_notes({ { pitch = 64, start = 0, length = 0.5 } })
  eq(api.clip_notes(id)[1].pitch, 64, "its notes are set as any clip's")
  launcher.set(id, "mode", "gate")
  launcher.set(id, "quantize", "1/8")
  launcher.set(id, "legato", true)
  local c = launcher.clip(t.id, 2)
  eq(c.mode .. " " .. c.quantize .. " " .. tostring(c.legato), "gate 1/8 true", "how it launches")
  fails(function() launcher.set(id, "quantize", "3 bars") end, "quantize", "an unknown quantize")
  fails(function() api.clip_set(id, "start", 4) end, "starts at 0", "a slot's clip has no place in time")
  launcher.move(id, nil, 0)
  eq(launcher.clip(t.id, 0).id, id, "moved to another row")
  local other = paw.add_track({ name = "Other" })
  launcher.move(id, other.id, 0)
  eq(#api.cue_list(t.id) .. #api.cue_list(other.id), "01", "to another track")
  api.clip_remove(id)
  eq(#api.cue_list(other.id), 0, "and removed")
end)

test("launcher: a clip on the timeline is copied into a slot, and a track's copy keeps its slots", function()
  start()
  local t = paw.add_track({ name = "Bass" })
  local clip = t:add_clip({ start = 8, length = 4, notes = { { pitch = 40, start = 1, length = 1 } } })
  local copy = launcher.copy(clip.id, t.id, 1)
  eq(api.clip_get(copy).start, 0, "it starts at 0")
  eq(api.clip_notes(copy)[1].start, 1, "with the notes where they were in it")
  eq(#api.clip_list(t.id), 1, "the original stays")
  local snap = t:snapshot()
  local twin = paw.restore_track(snap)
  eq(#api.cue_list(twin.id) .. " " .. #api.clip_list(twin.id), "1 1", "the copy of the track has the slot too")
  eq(launcher.clip(twin.id, 1) ~= nil, true, "in the same row")
end)

test("launcher: slots are saved, opened and undone with the project", function()
  start()
  local t = paw.add_track({ name = "Pad" })
  local id = launcher.add(t.id, 3, { length = 8, notes = { { pitch = 50, start = 0, length = 2 } } })
  launcher.set(id, "mode", "toggle")
  launcher.set_quantize("1/4")
  launcher.set_scene_name(3, "Drop")
  api.undo_checkpoint()
  local path = T.scratch .. "/launcher.json"
  api.project_save(path)
  paw.project.new()
  api.project_load(path)
  local slot = launcher.clip(api.track_list()[1], 3)
  eq(slot.slot .. " " .. slot.length .. " " .. slot.mode, "3 8 toggle", "the slot comes back")
  eq(api.clip_notes(slot.id)[1].pitch, 50, "with its notes")
  eq(launcher.quantize(), "1/4", "and the project's quantize")
  eq(launcher.scene_name(3) .. " " .. launcher.scene_name(0), "Drop Scene 1", "and the scenes' names")
  eq(launcher.rows() >= 5, true, "a row more than the last that is used")
  api.clip_remove(slot.id)
  api.undo_checkpoint()
  eq(#api.cue_list(api.track_list()[1]), 0, "emptied")
  api.undo()
  eq(#api.cue_list(api.track_list()[1]), 1, "and back with undo")
  local _ = id
end)

-- Launching ------------------------------------------------------------------

test("launcher: a launch lands on the next bar and the timeline falls silent meanwhile", function()
  start()
  local t, id = synth("Lead", 0, 69)
  t:add_clip({ start = 0, length = 64, notes = { { pitch = 45, start = 0, length = 64 } } })
  paw.transport.seek(0)
  paw.transport.play()
  until_(function() return paw.transport.position > 0.5 end, "the song to play", 10000)
  launcher.launch(t.id, 0)
  until_(function() return state(t.id).queued == 0 or state(t.id).slot == 0 end, "the launch to be queued", 5000)
  local s = state(t.id)
  if s.queued then eq(s.at, 4, "queued for the next bar") end
  until_(function() return state(t.id).slot == 0 end, "the clip to start", 10000)
  eq(state(t.id).since, 4, "it began on the bar")
  eq(launcher.playing(t.id), 0, "the track plays the slot")
  near(state(t.id).length, 4, 1e-9, "its loop's length")
  launcher.stop(t.id)
  until_(function() return state(t.id).stopped end, "the track to stop", 10000)
  eq(state(t.id).since % 4, 0, "on a bar")
  launcher.back(t.id)
  until_(function() return launcher.playing(t.id) == "arrangement" end, "the timeline again", 10000)
  T.stop()
  local _ = id
end)

test("launcher: launching while stopped starts the song and the clip at once, and stopping the song ends it", function()
  start()
  local t = synth("Lead", 1)
  paw.transport.seek(2)
  launcher.launch(t.id, 1)
  eq(paw.transport.playing, true, "the song plays")
  until_(function() return state(t.id).slot == 1 end, "the clip to start", 5000)
  near(state(t.id).since, 2, 1e-9, "where the playhead was")
  T.stop()
  until_(function() return launcher.playing(t.id) == "arrangement" end, "the timeline again", 5000)
end)

test("launcher: a scene launches its row together and stops tracks with nothing in it", function()
  start()
  local a = synth("A", 0, 60)
  launcher.add(a.id, 1, { length = 4, notes = { { pitch = 62, start = 0, length = 1 } } })
  local b = synth("B", 0, 64)
  local c = synth("C", 1, 67)
  launcher.scene(0)
  until_(function() return state(a.id).slot == 0 and state(b.id).slot == 0 end, "the first scene", 5000)
  eq(state(a.id).since, state(b.id).since, "together")
  eq(launcher.playing(c.id), "arrangement", "a track without a clip in the row is left alone")
  launcher.scene(1)
  until_(function() return state(a.id).slot == 1 and state(c.id).slot == 1 end, "the second scene", 10000)
  eq(state(a.id).since, state(c.id).since, "together again")
  until_(function() return state(b.id).stopped end, "B to stop", 5000)
  eq(state(b.id).since, state(a.id).since, "on the same boundary")
  launcher.stop()
  until_(function() return state(a.id).stopped and state(c.id).stopped end, "every clip to stop", 10000)
  launcher.back()
  until_(function() return next(launcher.state()) == nil end, "every track back", 10000)
  T.stop()
end)

test("launcher: a toggle clip stops when pressed again and a gate clip when let go", function()
  start()
  local t, id = synth("Lead", 0)
  launcher.set(id, "mode", "toggle")
  launcher.set(id, "quantize", "off")
  launcher.press(t.id, 0)
  until_(function() return state(t.id).slot == 0 end, "the toggle to start", 5000)
  launcher.press(t.id, 0)
  until_(function() return state(t.id).stopped end, "the toggle to stop", 5000)
  launcher.set(id, "mode", "gate")
  launcher.press(t.id, 0)
  until_(function() return state(t.id).slot == 0 end, "the gate to start", 5000)
  launcher.release(t.id, 0)
  until_(function() return state(t.id).stopped end, "the gate to stop", 5000)
  T.stop()
end)

test("launcher: a slot's quantize wins over the project's and a launch's over both", function()
  start()
  local t, id = synth("Lead", 0)
  launcher.set_quantize("4bars")
  launcher.set(id, "quantize", "1/16")
  paw.transport.seek(1.1)
  paw.transport.play()
  launcher.launch(t.id, 0)
  until_(function() return state(t.id).slot == 0 end, "the clip to start", 5000)
  local since = state(t.id).since
  eq(since > 1.1 and since <= 1.5 and (since * 4) % 1 == 0, true, "on a sixteenth: " .. since)
  launcher.launch(t.id, 0, { quantize = "bar" })
  until_(function() return state(t.id).since ~= since end, "the clip to start again", 10000)
  eq(state(t.id).since % 4, 0, "on a bar")
  T.stop()
end)

-- Rendering and capturing ------------------------------------------------------

test("launcher: a render plays the timeline, not what is launched", function()
  start()
  local t = synth("Lead", 0, 69)
  launcher.launch(t.id, 0)
  until_(function() return state(t.id).slot == 0 end, "the clip to start", 5000)
  local info = render({ start = 0, ["end"] = 4, tail = 0, bits = 16 })
  local left = T.channel_peaks(info)
  eq(left, 0, "the track has nothing on its timeline")
  T.stop()
end)

test("launcher: a captured performance is written into the timeline on its boundaries and renders there", function()
  start()
  local t = synth("Lead", 0, 69)
  local b = synth("Bass", 0, 45)
  b:add_clip({ start = 0, length = 32, notes = { { pitch = 33, start = 0, length = 32 } } })
  launcher.capture(true)
  paw.transport.seek(0)
  paw.transport.play()
  until_(function() return paw.transport.position > 0.3 end, "the song to play", 10000)
  launcher.launch(t.id, 0)
  until_(function() return state(t.id).slot == 0 end, "the clip to start", 10000)
  launcher.stop(b.id)
  until_(function() return paw.transport.position > 9 end, "two bars of it", 20000)
  T.stop()
  launcher.capture(false)
  local clips = api.clip_list(t.id)
  eq(#clips, 1, "one clip for the stretch it played")
  eq(clips[1].start, 4, "from the bar it began on")
  eq(clips[1].loop, true, "looping as the slot did")
  near(clips[1].loop_length, 4, 1e-9, "every four beats")
  local bass = api.clip_list(b.id)
  eq(#bass, 2, "the stopped track's timeline is cleared while it was stopped")
  eq(bass[1].start .. " " .. bass[1].length, "0 8", "up to the bar it stopped on, the one after the lead began")
  eq(bass[2].start > 9, true, "and from where the song stopped")
  -- Rendered alone, the lead starts on the second bar, to the frame.
  local info = render({ start = 0, ["end"] = 8, tail = 0, bits = 16, tracks = { t.id } })
  local bar = 2 * info.sample_rate -- a bar at 120 BPM, in frames
  local first = first_sound(info)
  eq(first >= bar and first <= bar + 2, true, "the first sound at frame " .. first .. ", the bar at " .. bar)
  api.undo()
  eq(#api.clip_list(t.id), 0, "one undo takes the capture away")
end)

-- Recording into a slot --------------------------------------------------------

test("launcher: recording into an empty slot keeps a bar from the boundary and plays it on in step", function()
  start()
  api.engine_restart({ test_input = { frequency = 440, level = -12, channels = 2 } })
  local ok, err = xpcall(function()
    local t = paw.add_track({ name = "Voice" })
    t.input = "1/2"
    paw.transport.seek(0.5)
    launcher.record(t.id, 2)
    eq(launcher.recording ~= nil, true, "recording")
    eq(launcher.recording.from, 4, "from the next bar")
    until_(function() return launcher.clip(t.id, 2) ~= nil end, "the bar to be recorded", 30000)
    eq(launcher.recording, nil, "and the recording is over")
    local slot = launcher.clip(t.id, 2)
    eq(slot ~= nil and slot.kind, "audio", "the slot holds the recording")
    near(slot.length, 4, 1e-9, "a bar of it")
    eq(#api.clip_list(t.id), 0, "and the take left the timeline")
    until_(function() return state(t.id).slot == 2 end, "it to play", 5000)
    -- In step: as if it had played since the bar it began on.
    local s, position = state(t.id), paw.transport.position
    local off = math.abs((s.phase - (position - 4) + 2) % 4 - 2)
    near(off, 0, 0.2, "where it is in its loop, beats off")
    T.stop()
    api.undo()
    eq(launcher.clip(t.id, 2), nil, "undone")
  end, debug.traceback)
  api.engine_restart({})
  if not ok then error(err, 0) end
end)

-- Controllers ------------------------------------------------------------------

test(
  "launcher: a pad learned in the session view launches the slot under the cursor, and others the scene and stop",
  function()
    start()
    local t = synth("Drums", 1)
    local note = function(pitch, on)
      paw.midi.inject({ type = on == false and "note_off" or "note_on", pitch = pitch, velocity = 100, channel = 10 })
      paw.flush()
    end
    paw.ui.show("session")
    paw.ui.focus("session")
    paw.cursor.set_track(t.id)
    launcher.row = 1
    paw.cmd("learn")
    eq(paw.learn.learning and paw.learn.learning.target, "launch", "waiting for a pad")
    note(36)
    note(36, false)
    local b = paw.learn.bindings()[1]
    eq(b.source .. " " .. b.number .. " " .. b.target .. " " .. b.slot, "note 36 launch 1", "the binding")
    eq(launcher.playing(t.id), "arrangement", "the press that taught it launched nothing")
    note(36)
    until_(function() return state(t.id).slot == 1 end, "the pad to launch the clip", 5000)
    paw.learn.bind({ cc = 20, channel = 10 }, { target = "stop" })
    paw.midi.inject({ type = "cc", number = 20, value = 1, channel = 10 })
    paw.flush()
    until_(function() return state(t.id).stopped end, "the button to stop every clip", 10000)
    fails(
      function() paw.learn.bind({ note = 40 }, { track = t.id, target = "volume" }) end,
      "moves nothing",
      "a key moves nothing"
    )
    paw.commands.exec("learn volume")
    note(50)
    eq(paw.learn.learning ~= nil, true, "a key is not learned for a fader")
    paw.learn.cancel()
    T.stop()
    paw.ui.hide("session")
  end
)

-- The session view and the window's gestures ----------------------------------

local function screen(w, h) return table.concat(api.ui_snapshot(w or 120, h or 36), "\n") end

test("launcher: the session view shows the slots and scenes, and its keys launch and stop", function()
  start()
  local t = synth("Lead", 0)
  launcher.set_scene_name(0, "Verse")
  paw.keymap.feed("<leader>vs")
  eq(paw.ui.focused, "session", "shown and focused")
  paw.cursor.set_track(t.id)
  local text = screen()
  eq(text:find("Session", 1, true) ~= nil, true, "its title")
  eq(text:find("Verse", 1, true) ~= nil, true, "the scene's name")
  eq(text:find("Lead", 1, true) ~= nil, true, "the track's name")
  paw.keymap.feed("<CR>")
  until_(function() return state(t.id).slot == 0 end, "Enter to launch", 5000)
  eq(screen():find("1/1", 1, true) ~= nil, true, "what plays is shown, in which bar of its loop")
  paw.keymap.feed("S")
  until_(function() return state(t.id).stopped end, "S to stop", 10000)
  paw.keymap.feed("B")
  until_(function() return launcher.playing(t.id) == "arrangement" end, "B to go back", 10000)
  paw.keymap.feed("jo")
  eq(launcher.clip(t.id, 1) ~= nil, true, "o makes a clip in the next slot")
  paw.keymap.feed("yyjp")
  eq(launcher.clip(t.id, 2) ~= nil, true, "yanked and pasted into the one after")
  paw.keymap.feed("x")
  eq(launcher.clip(t.id, 2), nil, "x empties it")
  paw.keymap.feed("k~")
  eq(launcher.clip(t.id, 1).mode, "gate", "~ goes round the modes")
  paw.keymap.feed("g~")
  eq(launcher.clip(t.id, 1).legato, true, "g~ turns legato on")
  paw.keymap.feed("r")
  eq(api.track_get(t.id).armed, true, "r arms the track, as in every view")
  eq(#paw.ui.keybar.check(), 0, "every key the key bar shows is mapped")
  T.stop()
  paw.ui.hide("session")
end)

test(
  "launcher: the session view's pointer chooses, opens, moves and launches slots, and takes a clip dropped on it",
  function()
    start()
    local act = require("launcher.view").act
    local t = paw.add_track({ name = "Keys" })
    local u = paw.add_track({ name = "Bass" })
    local clip = t:add_clip({ start = 4, length = 4, notes = { { pitch = 60, start = 0, length = 1 } } })
    paw.ui.show("session")
    local id = act.open(t.id, 3)
    eq(launcher.clip(t.id, 3).id, id, "a double click on an empty slot makes a clip there")
    eq(paw.ui.views:get("pianoroll"):clip().id, id, "and opens it in the piano roll")
    paw.ui.hide("pianoroll")
    act.move(id, u.id, 5, false)
    eq(launcher.clip(u.id, 5).id, id, "dragged to another track's slot")
    act.move(id, t.id, 1, true)
    eq(launcher.clip(t.id, 1) ~= nil and launcher.clip(u.id, 5) ~= nil, true, "with Ctrl, a copy")
    act.choose(u.id, 0)
    eq(
      launcher.row .. " " .. paw.cursor.track_id() .. " " .. paw.ui.focused,
      "0 " .. u.id .. " session",
      "a click chooses"
    )
    -- A clip of the timeline let go over the view, as the window passes it on.
    api.ui_snapshot(120, 36)
    local win
    for _, w in ipairs(require("paw.layout").windows(paw.ui.layout)) do
      if w.view == "session" then win = w end
    end
    local cell = paw.canvas.cell
    paw.cursor.set_track(t.id)
    api.ui_snapshot(120, 36)
    -- The first column, the second row of slots: under the title and the names.
    paw.panes.pointer(
      win.id,
      { kind = "drop", x = 6 * cell.w, y = 3 * cell.h, clip = clip.id },
      { cell = cell, cols = 120, rows = 12 }
    )
    local dropped = launcher.clip(t.id, 1)
    eq(dropped ~= nil and api.clip_notes(dropped.id)[1].pitch, 60, "a copy of the dropped clip is in the slot")
    eq(#api.clip_list(t.id), 1, "and the clip stays on the timeline")
    act.press(u.id, 0)
    until_(
      function() return (launcher.state()[u.id] or {}).queued == "stop" or (launcher.state()[u.id] or {}).stopped end,
      "a press on an empty slot to stop",
      5000
    )
    launcher.stop(nil)
    launcher.back(nil)
    until_(function() return next(launcher.state()) == nil end, "all back", 10000)
    T.stop()
    paw.ui.hide("session")
  end
)

-- The extension and the core ---------------------------------------------------

test("launcher: the launcher unloads and loads again, and the project keeps its slots without it", function()
  start()
  local t = synth("Lead", 1)
  launcher.set_scene_name(1, "Chorus")
  eq(paw.commands.get("launch") ~= nil, true, "its commands")
  local ok, err = paw.ext.unload("launcher")
  eq(ok, true, "unloaded: " .. tostring(err))
  eq(paw.commands.get("launch"), nil, "its commands are gone")
  eq(paw.ui.views:get("session"), nil, "and its view")
  eq(paw.learn.triggers:get("launch"), nil, "and its controller buttons")
  eq(#api.cue_list(t.id), 1, "the clip stays in the project")
  local path = T.scratch .. "/launcher-without.paw"
  api.project_save(path)
  api.project_load(path)
  eq(#api.cue_list(api.track_list()[1]), 1, "and is saved and opened without the extension")
  paw.ext.load("extensions/launcher")
  launcher = require("launcher")
  eq(
    launcher.clip(api.track_list()[1], 1) ~= nil and launcher.scene_name(1),
    "Chorus",
    "loaded again, the slot and the scene are there"
  )
end)

-- Moved here with the session view: the pointer in the terminal, Escape,
-- VCAs, and the command picker in the view -------------------------------------

local W, H = 140, 44
local function shot(height) return api.ui_snapshot(W, height or H) end
local function m(kind, x, y, button, mods)
  paw.ui.mouse({ kind = kind, x = x, y = y, button = button or "left", mods = mods or "" })
end
local function click(x, y, button, mods)
  m("down", x, y, button, mods)
  m("up", x, y, button, mods)
end
local function drag(x0, y0, x1, y1, button, mods)
  m("down", x0, y0, button, mods)
  m("drag", x0 + (x1 > x0 and 1 or x1 < x0 and -1 or 0), y0 + (y1 > y0 and 1 or y1 < y0 and -1 or 0), button, mods)
  m("drag", x1, y1, button, mods)
  m("up", x1, y1, button, mods)
end
--- Let time pass since the last press, so that the next is not a double click.
local function apart() paw.mouse.forget() end

test("launcher: Escape in the session view cancels and stays there", function()
  start()
  paw.ui.show("session")
  paw.ui.focus("session")
  paw.keymap.feed("3d")
  paw.keymap.feed("<Esc><Esc>")
  eq(
    paw.ui.focused .. " " .. paw.keymap.pending() .. " " .. paw.keymap.mode,
    "session  n",
    "the count and operator are cancelled, the view stays"
  )
  paw.ui.hide("session")
end)

test(
  "launcher: the session view: a click chooses a slot, its play mark launches it, a double click makes a clip, a drag moves one",
  function()
    start()
    local opt_mouse = paw.opt.mouse
    paw.opt.mouse = true
    T.after(function() paw.opt.mouse = opt_mouse end)
    local t = paw.add_track({ name = "Keys" })
    t:add_device("synth")
    launcher.new_clip(t.id, 0)
    paw.ui.show("session")
    shot()
    local rect
    for _, r in ipairs(paw.ui.rects) do
      if r.name == "session" then rect = r end
    end
    local view = paw.ui.views:get("session")
    local col = view.geometry.columns[1]
    local function slot(row) return rect.x + col.x, rect.y + 1 + (row - view.top) + 1 end
    local x, y = slot(1)
    click(x + 4, y)
    eq(launcher.row .. " " .. paw.ui.focused, "1 session", "a click chooses the slot")
    apart()
    x, y = slot(2)
    click(x + 4, y)
    click(x + 4, y)
    eq(launcher.clip(t.id, 2) ~= nil, true, "a double click on an empty slot makes a clip there")
    eq(paw.ui.focused, "pianoroll", "and opens it")
    paw.ui.hide("pianoroll")
    shot()
    apart()
    x, y = slot(0)
    click(x, y)
    T.until_(function()
      local s = launcher.state()[t.id] or {}
      return s.slot == 0 or s.queued == 0
    end, "the play mark launches the clip")
    launcher.stop(nil)
    T.stop()
    apart()
    local _, y3 = slot(3)
    drag(x + 4, y, x + 4, y3)
    eq(launcher.clip(t.id, 3) ~= nil and launcher.clip(t.id, 0) == nil, true, "a drag moves the clip to another slot")
    paw.ui.hide("session")
  end
)

test("launcher: the session view leaves VCAs out", function()
  start()
  local a, b = paw.add_track({ name = "Alpha" }), paw.add_track({ name = "Beta" })
  paw.vca.make({ a }, "Faders")
  paw.ui.show("session")
  paw.ui.focus("session")
  paw.cursor.set_track(b)
  local screen = table.concat(api.ui_snapshot(120, 30), "\n")
  paw.ui.hide("session")
  paw.ui.focus("arrange")
  local function count(word) return select(2, screen:gsub(word, "")) end
  eq(count("Beta") .. " " .. count("Faders"), "2 1", "tracks are columns, besides their rows; the VCA is a row only")
end)

test(
  "launcher: the command picker ranks by use and by the focused view, with exact and prefix matches first",
  function()
    start()
    paw.keymap.feed("<Esc><Esc>")
    if paw.ui.float then paw.ui.close() end
    paw.state.command_uses = nil
    local pick = paw.pick
    local function order(view, query)
      paw.ui.focus(view)
      paw.pick("commands")
      paw.keymap.feed(query)
      local out = {}
      for i, line in ipairs(pick.state().matches) do
        out[line:match("^(%S+)")] = i
      end
      paw.keymap.feed("<Esc>")
      return out
    end
    local rank = order("arrange", "name")
    eq(
      rank["track.rename"] < rank["scene.name"],
      true,
      "in the arrange view its own rename comes before the session's scene.name"
    )
    rank = order("session", "name")
    eq(rank["scene.name"] < rank["track.rename"], true, "in the session view the scene's name does")
    for _ = 1, 10 do
      paw.commands.used("track.rename")
    end
    rank = order("session", "name")
    eq(rank["track.rename"] < rank["scene.name"], true, "what is used often goes first, in any view")
    eq(paw.commands.uses("track.rename"), 10, "the count is kept")
    for _ = 1, 50 do
      paw.commands.used("scene.name")
    end
    rank = order("arrange", "scene.name")
    eq(rank["scene.name"], 1, "an exact match is first however much another is used")
    paw.state.command_uses = nil
    paw.ui.focus("arrange")
  end
)

test("launcher: the README names every command and key of the extension", function()
  start()
  local readme = T.read_file("extensions/launcher/README.md")
  local commands, keys = 0, 0
  for _, part in ipairs(paw.ext.provides("launcher")) do
    for _, item in ipairs(part.items) do
      if part.kind == "commands" then
        commands = commands + 1
        local named = readme:find("`" .. item .. "`", 1, true) or readme:find("`" .. item .. " ", 1, true)
        eq(named ~= nil, true, "README names " .. item)
      elseif part.kind == "keys" then
        local lhs, scope = item:match("^(%S+) %((.*)%)$")
        lhs = lhs:gsub("<leader>", "<Space>")
        if not (scope or ""):find("classic", 1, true) then
          keys = keys + 1
          eq(
            readme:find("`" .. lhs .. "`", 1, true) ~= nil,
            true,
            "README names the key " .. lhs .. " (" .. tostring(scope) .. ")"
          )
        end
      end
    end
  end
  eq(commands >= 17 and keys >= 30, true, "commands and keys found: " .. commands .. " " .. keys)
end)

test("launcher: an export to REAPER or DAWproject reports the clips of the slots as not written", function()
  start()
  local t = synth("Lead", 0)
  launcher.add(t.id, 3, { length = 4 })
  for _, ext in ipairs({ "rpp", "dawproject" }) do
    if not paw.ext.loaded.interop then paw.ext.load("extensions/interop") end
    local result =
      require("interop." .. ext).export(T.scratch .. "/launcher-export." .. (ext == "rpp" and "rpp" or "dawproject"))
    local found
    for _, g in ipairs(result.report:data()) do
      if g.name:find("clip launcher", 1, true) then found = g end
    end
    eq(found ~= nil and #found.items, 1, ext .. ": the track with two clips in slots is named")
  end
end)

test(
  "launcher: while the song plays, the session view is drawn again as a live part, the same as drawn whole",
  function()
    start()
    local t = synth("Lead", 0, 60, 2)
    paw.ui.show("session")
    paw.cursor.set_track(t.id)
    launcher.launch(t.id, 0, { quantize = "off" })
    until_(function() return (launcher.state()[t.id] or {}).slot == 0 end, "the clip to start", 5000)
    T.stop()
    -- The stop returns before the engine stops: wait until the engine has
    -- sent the track back to its timeline, so both drawings see it stopped.
    until_(function() return (launcher.state()[t.id] or {}).slot == nil end, "the stop to send the track back")
    local W, H = 120, 40
    -- The drawings come one after the other, and a meter falls and a held
    -- peak lets go in between (a loaded machine): the meters stand still.
    local meter = api.track_meter
    api.track_meter = function() return 0.5, 0.25 end
    local draw = require("paw.draw")
    local function still()
      draw.clear_peak(0)
      for _, id in ipairs(api.track_list()) do
        draw.clear_peak(id)
      end
    end
    still()
    local first = api.ui_frame_snapshot(W, H)
    eq(first.live > 0, true, "live parts")
    paw.transport.position = 3
    still()
    local moved = api.ui_frame_snapshot(W, H, true)
    still()
    local whole = api.ui_frame_snapshot(W, H)
    api.track_meter = meter
    eq(moved ~= nil, true, "drawn by its live parts only, with the session view shown")
    for row = 1, H do
      eq(moved.cells[row], whole.cells[row], "row " .. row .. ":\n" .. moved.text[row] .. "\n" .. whole.text[row])
    end
    paw.ui.hide("session")
  end
)

test(
  "launcher: in a window, the session view's scene is drawn again only when what plays fills another cell",
  function()
    start()
    local t = synth("Lead", 0, 60, 2)
    paw.ui.show("session")
    paw.cursor.set_track(t.id)
    api.ui_snapshot(120, 36)
    local view = paw.ui.views:get("session")
    launcher.launch(t.id, 0, { quantize = "off" })
    until_(function() return state(t.id).slot == 0 end, "the clip to start", 5000)
    -- Its key (`paw.scene`) says what the window shows of what plays: it
    -- stays while the slot fills no new cell, as the song plays.
    local samples, changes, last = 0, 0, nil
    until_(function()
      local key = view:scene_key()
      samples = samples + 1
      if key ~= last then
        changes, last = changes + 1, key
      end
      return changes >= 3
    end, "the slot to fill three cells", 8000)
    eq(type(last), "string", "a key")
    eq(changes < samples / 2, true, "the same key for many ticks: " .. changes .. " changes in " .. samples)
    T.stop()
    paw.ui.hide("session")
  end
)
