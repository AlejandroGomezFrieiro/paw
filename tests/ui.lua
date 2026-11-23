-- How the terminal UI looks: the things that should stay true however the
-- drawing changes.
local T = ...
local test, eq, fresh, expect_screen = T.test, T.eq, T.fresh, T.expect_screen
local paw = require("paw")
local api = paw.api

--- The tutor loaded for this test: the welcome page names `:tutor` when it
--- is. Whether a test before loaded it depends on the order of the tests.
local function with_tutor()
  if paw.ext.loaded.tutor then return end
  paw.ext.load_bundled("tutor")
  T.after(function() paw.ext.unload("tutor") end)
end

local function screen(w, h) return table.concat(api.ui_snapshot(w or 120, h or 36), "\n") end

test(
  "the key bar only shows keys that are mapped",
  function() eq(table.concat(paw.ui.keybar.check(), ", "), "", "keys shown with nothing mapped to them") end
)

test("the bottom line shows the keys for the focused view, and gives way to messages", function()
  fresh()
  paw.ui.message = nil
  paw.ui.focus("arrange")
  local last = function()
    local lines = api.ui_snapshot(120, 30)
    return lines[#lines]
  end
  eq(last():find("Space Space play", 1, true) ~= nil, true, "the arrange view's keys: " .. last())
  eq(last():find("Space mm mixer", 1, true) ~= nil, true, "with the leader shown as it is typed")
  paw.notify("hello")
  eq(last():find("hello", 1, true) ~= nil, true, "a message takes the line")
  eq(last():find("Space play", 1, true), nil, "instead of the keys")
  paw.ui.message = nil
  paw.ui.focus("mixer")
  eq(last():find("j row", 1, true) ~= nil, true, "another view has its own")
  paw.ui.hide("mixer")
  paw.ui.focus("arrange")
  paw.opt.keybar = false
  eq(last():find("Space play", 1, true), nil, "and the option turns it off")
  paw.opt.keybar = true
end)

test("a new project says how to begin", function()
  fresh()
  with_tutor()
  paw.cmd("view.only")
  paw.ui.message = nil
  expect_screen("welcome", 80, 20)
  paw.add_track({ name = "one" })
  paw.flush()
  expect_screen("one_track", 80, 20)
end)

test("the welcome page keeps each key apart from what it does, at any width and key length", function()
  fresh()
  with_tutor()
  paw.cmd("view.only")
  paw.ui.message = nil
  -- The rows of the page only: the ruler and the master are in "welcome".
  expect_screen("welcome_60", 60, 20, { rows = { 3, 16 } })
  expect_screen("welcome_120", 120, 20, { rows = { 3, 16 } })
  -- A leader of the user's makes the widest key of the page.
  T.keys(":set leader=<lt>C-A-S-Space><CR>")
  paw.ui.message = nil
  local keys = { "o", "a", "i Enter", "Ctrl-Alt-Shift-Space Space", "Ctrl-Alt-Shift-Space f:", ":help" }
  for _, width in ipairs({ 60, 80, 120 }) do
    local rows = api.ui_snapshot(width, 24)
    for _, key in ipairs(keys) do
      local apart = false
      for _, row in ipairs(rows) do
        apart = apart or row:find("^%s+" .. key:gsub("%p", "%%%0") .. "%s%s+%S") ~= nil
      end
      eq(apart, true, string.format("at %d columns, two spaces at least after the key %q", width, key))
    end
  end
end)

test("tracks take colours in turn, or the one they are given", function()
  fresh()
  local a, b = paw.add_track({ name = "a" }), paw.add_track({ name = "b" })
  local first, second = paw.draw.track_colour(a:get(), 1), paw.draw.track_colour(b:get(), 2)
  eq(first ~= second, true, "two tracks, two colours")
  a.color = "#123456"
  eq(paw.draw.track_colour(a:get(), 1), "#123456", "a track's own colour wins")
  local hue = paw.draw.hue("#123456")
  eq(type(hue.title), "string", "shades of it are highlight groups")
  eq(hue.title, paw.draw.hue("#123456").title, "made once")
  eq(paw.draw.mix("#000000", "#ffffff", 0.5), "#808080", "colours mix")
end)

test("clips show their notes, and the piano roll its keyboard and velocities", function()
  fresh()
  local t = paw.add_track({ name = "t" })
  local clip = t:add_clip({
    start = 0,
    length = 4,
    name = "riff",
    notes = {
      { pitch = 60, start = 0, length = 1, velocity = 120 },
      { pitch = 72, start = 2, length = 1, velocity = 40 },
    },
  })
  paw.flush()
  local text = screen()
  eq(text:find("riff", 1, true) ~= nil, true, "the clip's name")
  eq(text:find("▀", 1, true) ~= nil or text:find("▄", 1, true) ~= nil, true, "and its notes as a small roll")
  local rows = paw.draw.miniroll(clip:notes(), 8, 2, 2)
  eq(#rows, 2, "a roll of as many rows as asked for")
  eq(api.str_width(rows[1]), 8, "and as wide")
  eq(rows[2]:sub(1, 3) ~= "   ", true, "the low note at the bottom left")
  paw.ui.views:get("pianoroll"):edit(clip)
  text = screen(120, 90)
  eq(text:find("C4", 1, true) ~= nil, true, "the keyboard names its Cs")
  eq(text:find("vel", 1, true) ~= nil, true, "velocities have a lane when there is room")
  paw.ui.hide("pianoroll")
  paw.ui.focus("arrange")
end)

test("a track is given a colour by name", function()
  fresh()
  local t = paw.add_track({ name = "t" })
  paw.cursor.set_track(t)
  paw.cmd("track.color", { "teal" })
  eq(t.color, require("paw.theme").hues[6], "a name from the theme")
  paw.cmd("track.color", { "#ff8800" })
  eq(t.color, "#ff8800", "or any colour")
  paw.cmd("track.color", { "puce" })
  eq(t.color, "#ff8800", "a name it does not know changes nothing")
  paw.cmd("track.color", { "none" })
  eq(t.color, nil, "and none goes back to the theme's")
end)

test("Tab completes what a command takes, after its name", function()
  fresh()
  local t = paw.add_track({ name = "t" })
  paw.cursor.set_track(t)
  T.keys(":track.color te<Tab><CR>")
  eq(t.color, require("paw.theme").hues[6], "`te` and Tab is teal")
  T.keys(":track.col<Tab> no<Tab><CR>")
  eq(t.color, nil, "after the command's own name was completed")
end)

test("a track's header shows its input, the level arriving there, and a monitor switch", function()
  api.engine_restart({ backend = "null", test_input = { frequency = 440, level = -12, channels = 2 } })
  local ok, err = pcall(function()
    fresh()
    paw.cmd("view.only")
    paw.ui.focus("arrange")
    -- The input is on the fourth row of a track's header.
    paw.opt.track_height = 4
    local t = paw.add_track({ name = "Gtr" })
    t.input = "1/2"
    T.next_block(10)
    local text = screen(150, 36)
    eq(text:find("test signal · 1/2", 1, true) ~= nil, true, "the input by device and channels:\n" .. text)
    eq(text:find("M S R I", 1, true) ~= nil, true, "I for monitoring after mute, solo and arm")
    local glyph = paw.ui.views:get("arrange").level_glyph(paw.audio.level(t:get()))
    eq(glyph ~= "·", true, "the level shows before the track is armed or monitored")
    eq(text:find(glyph .. " test signal", 1, true) ~= nil, true, "in front of the input")
  end)
  api.engine_restart({ backend = "null" })
  assert(ok, err)
end)

test("I opens a list of the track's inputs to choose from", function()
  api.engine_restart({ backend = "null", test_input = { frequency = 440, level = -12, channels = 2 } })
  local ok, err = pcall(function()
    fresh()
    paw.ui.focus("arrange")
    local t = paw.add_track({ name = "Gtr" })
    paw.cursor.set_track(t)
    paw.keymap.feed("I")
    local text = screen()
    eq(text:find("Input of Gtr", 1, true) ~= nil, true, "a picker:\n" .. text)
    eq(text:find("Monitor", 1, true) ~= nil, true, "with monitoring first")
    eq(text:find("MIDI channel", 1, true) ~= nil, true, "and MIDI under its own heading")
    paw.keymap.feed("1/2<CR>")
    eq(t.input, "1/2", "typing part of one and Enter chooses it")
  end)
  paw.ui.close()
  api.engine_restart({ backend = "null" })
  assert(ok, err)
end)

local function status_line(w, h)
  for _, line in ipairs(api.ui_snapshot(w, h)) do
    if line:find("bpm", 1, true) or line:find("NOR", 1, true) then return line end
  end
  return ""
end

test("the status line keeps its segments by width and never drops the project's name", function()
  fresh()
  paw.cmd("view.only")
  paw.add_track({ name = "t" })
  paw.flush()
  local wide = status_line(150, 40)
  eq(wide:find("NORMAL", 1, true) ~= nil, true, "the mode in full: " .. wide)
  eq(wide:find("grid 1/4", 1, true) ~= nil, true, "the grid as a note value at 150: " .. wide)
  eq(wide:find("cpu", 1, true) ~= nil, true, "the engine's load at 150")
  eq(wide:find("48k", 1, true) ~= nil, true, "and the engine at 150")
  local mid = status_line(95, 40)
  eq(mid:find("grid", 1, true), nil, "no grid under 100: " .. mid)
  eq(mid:find("48k", 1, true), nil, "no engine under 120")
  eq(mid:find("cpu", 1, true) ~= nil, true, "the load down to 90")
  -- Under 80 a short mode, under 90 no load, down to 70 the tempo.
  expect_screen("status_narrow", 70, 20, { rows = { 19, 19 } })
  paw.project.name = "a rather long name for a song that goes on and on"
  local cut = status_line(70, 20)
  eq(cut:find("a rather", 1, true) ~= nil, true, "a long name is cut, not dropped: " .. cut)
  eq(api.str_width(cut) <= 70, true, "and the line still fits")
  -- Toggles show only while they are on.
  eq(wide:find("loop", 1, true), nil, "no loop while it is off")
  paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = 8, 16, true
  eq(status_line(150, 40):find("loop 3", 1, true) ~= nil, true, "the loop's bars while it is on")
  paw.transport.loop_enabled = false
end)

test("a screen too small to draw on says so, with the status line", function()
  fresh()
  paw.ui.message = nil
  expect_screen("too_small", 52, 14)
  eq(table.concat(api.ui_snapshot(60, 16), "\n"):find("too small", 1, true), nil, "60 by 16 is enough")
end)

test("colours fall back to the nearest of the 256 when the terminal has no 24-bit colour", function()
  local draw = paw.draw
  eq(draw.nearest256("#ff0000"), 196, "pure red is in the cube")
  eq(draw.nearest256("#5fafd7"), 74, "a colour of the cube is itself")
  eq(draw.nearest256("#101216"), 233, "a near-black grey is a grey")
  eq(draw.nearest256("#8a91a3"), 246, "a cool grey stays grey, not lilac")
  local _, shade = draw.nearest256("#647133")
  eq(
    not (shade:sub(2, 3) == shade:sub(4, 5) and shade:sub(4, 5) == shade:sub(6, 7)),
    true,
    "a dull olive keeps a hue: " .. shade
  )
  local def = draw.term_def({ fg = "#ff0000", bg = "#101216", bold = true }, false)
  eq(def.fg .. " " .. def.bg .. " " .. tostring(def.bold), "196 233 true", "a group's colours become numbers")
  eq(draw.term_def({ fg = "#ff0000" }, true).fg, "#ff0000", "and stay as they are with 24-bit colour")
  paw.opt.termcolors = "256"
  eq(draw.truecolor(), false, "the option forces 256")
  paw.opt.termcolors = "true"
  eq(draw.truecolor(), true, "or 24-bit")
  paw.opt.termcolors = "auto"
end)

test("a highlight group that paw refused does not fail again when termcolors changes", function()
  eq(pcall(paw.ui.hl, {}, {}), false, "a table is not a group's name")
  -- The runner fails the test if the change of colours reports an error.
  paw.opt.termcolors = "256"
  paw.opt.termcolors = "auto"
end)

test("tracks fit their height to the screen, and the headers their width", function()
  fresh()
  paw.cmd("view.only")
  local arrange = paw.ui.views:get("arrange")
  for i = 1, 2 do
    paw.add_track({ name = "t" .. i })
  end
  paw.flush()
  eq(arrange:layout(120, 34).th, 3, "two tracks on a tall screen get three rows each, the most")
  for i = 3, 12 do
    paw.add_track({ name = "t" .. i })
  end
  paw.flush()
  eq(arrange:layout(120, 34).th, 2, "twelve get two, so that all of them fit")
  for i = 13, 40 do
    paw.add_track({ name = "t" .. i })
  end
  paw.flush()
  local many = arrange:layout(120, 34)
  eq(many.th .. " " .. many.rows[1].h, "1 1", "forty get one, the least")
  eq(#many.rows < 40, true, "and scroll")
  paw.opt.track_height = 2
  eq(arrange:layout(120, 34).th, 2, "a number in the option wins")
  paw.opt.track_height = "auto"
  eq(arrange.header_width(150), 26, "26 columns of header from 120 wide")
  eq(arrange.header_width(110), 22, "22 from 100")
  eq(arrange.header_width(85), 18, "18 from 80")
  eq(arrange.header_width(70), 12, "12 below")
end)

--- A song of `n` tracks of one clip each, the first two a group, with
--- the arrange view alone on the screen.
local function tracks_song(n)
  fresh()
  paw.cmd("view.only")
  paw.ui.views:get("arrange").scroll = 0
  local made = {}
  for i = 1, n - 1 do
    made[i] = paw.add_track({ name = "Track " .. i })
    made[i]:add_clip({ start = 0, length = 16, notes = { { pitch = 60, start = 0, length = 2 } } })
  end
  paw.groups.make({ made[1], made[2] }, "Group")
  paw.cursor.set_track(made[1])
  paw.flush()
end

test("with track_height auto, every track of a song of 7 fits on 100 by 30, three rows each", function()
  tracks_song(7)
  eq(paw.opt.track_height, "auto", "the option of a new start")
  expect_screen("seven_tracks", 100, 30, { rows = { 1, 28 }, styles = false })
end)

test("with track_height auto, a song of 11 tracks gets two rows a track and fits on 100 by 30", function()
  tracks_song(11)
  expect_screen("eleven_tracks", 100, 30, { rows = { 1, 28 }, styles = false })
end)

test("the selected track's chips read M S R I, lit when on", function()
  fresh()
  paw.cmd("view.only")
  local t = paw.add_track({ name = "Gtr" })
  t.mute = true
  paw.flush()
  expect_screen("chips", 150, 36, { rows = { 2, 4 }, cols = { 1, 28 } })
end)

test("with paw.opt.ascii the screen is drawn in plain ASCII", function()
  fresh()
  paw.cmd("view.only")
  local t = paw.add_track({ name = "t" })
  t:add_clip({ start = 0, length = 4, name = "c", notes = { { pitch = 60, start = 0, length = 1 } } })
  paw.flush()
  paw.ui.message = nil -- a message is text someone wrote, not drawing
  paw.opt.ascii = true
  local text = table.concat(api.ui_snapshot(120, 30), "\n")
  expect_screen("ascii", 60, 16, { styles = false })
  paw.opt.ascii = false
  eq(text:find("[\128-\255]"), nil, "no character outside ASCII:\n" .. text)
  eq(table.concat(api.ui_snapshot(120, 30), "\n"):find("│", 1, true) ~= nil, true, "and back to box drawing after")
end)

test("each cell of a clip shows its own time: the first note and the first sound fill the first cell", function()
  fresh()
  paw.cmd("view.only")
  paw.opt.zoom, paw.opt.track_height = 1, 4
  -- Two MIDI clips side by side, each with a note on its first beat; the
  -- first starts under the stopped playhead.
  local keys = paw.add_track({ name = "keys" })
  for _, start in ipairs({ 0, 4 }) do
    keys:add_clip({ name = "riff", start = start, length = 4, notes = { { pitch = 60, start = 0, length = 1 } } })
  end
  -- An audio clip whose sound starts at once, a beat after the playhead.
  local samples = {}
  for i = 1, 48000 * 2 do
    samples[i] = 0.5 * math.sin(i / 20)
  end
  local voice = paw.add_track({ name = "voice" })
  voice:add_clip({ name = "vox", file = T.write_wav(T.scratch .. "/first-cell.wav", samples), start = 1, length = 4 })
  paw.flush()
  paw.ui.message = nil
  -- The tracks' rows of the timeline, from the rule before it (column 15).
  T.keys("gg0")
  expect_screen("first_cell_zoom1", 60, 16, { rows = { 2, 9 }, cols = { 15, 31 } })
  T.keys("zizi")
  eq(paw.opt.zoom, 4, "two zi zoom to 4 columns a beat")
  expect_screen("first_cell_zoom4", 60, 16, { rows = { 2, 9 }, cols = { 15, 47 } })
end)

--- A wave of `seconds` at 48 kHz in the test's folder, whose level in each
--- half second is the next of `levels`, round and round.
local function stepped_wave(name, seconds, levels)
  local samples = {}
  for i = 1, math.floor(48000 * seconds) do
    local level = levels[math.floor(i / 24000) % #levels + 1]
    samples[i] = level * math.sin(i / 20)
  end
  return T.write_wav(T.scratch .. "/" .. name .. ".wav", samples)
end

test("each take lane shows its take's notes or sound under its time", function()
  fresh()
  paw.cmd("view.only")
  paw.opt.zoom, paw.opt.track_height = 2, 3
  -- A MIDI clip whose first take has two notes and whose second (playing)
  -- has one, and an audio clip whose takes are loud in turns.
  local keys = paw.add_track({ name = "keys" })
  local riff = keys:add_clip({
    name = "riff",
    start = 0,
    length = 4,
    notes = { { pitch = 60, start = 0, length = 1 }, { pitch = 64, start = 2, length = 1 } },
  })
  paw.takes.new(riff.id)
  riff:set_notes({ { pitch = 67, start = 1, length = 1 } })
  local voice = paw.add_track({ name = "voice" })
  local vox = voice:add_clip({ name = "vox", file = stepped_wave("loud-quiet", 2, { 0.9, 0.05 }), start = 0 })
  paw.takes.new(vox.id)
  api.clip_set(vox.id, { file = stepped_wave("quiet-loud", 2, { 0.05, 0.9 }) })
  api.undo_checkpoint()
  paw.flush()
  T.keys("gg0zt")
  T.keys("Gzt")
  paw.ui.message = nil
  expect_screen("take_lanes", 60, 24, { rows = { 2, 15 }, cols = { 1, 27 } })
end)

test("the status line says how much a selection holds, the same in each visual mode", function()
  fresh()
  paw.cmd("view.only")
  paw.opt.zoom, paw.opt.grid = 1, 4
  for _, name in ipairs({ "a", "b", "c" }) do
    paw.add_track({ name = name })
  end
  -- Each from bar 3 of the first track: bars 3 and 4 of it, the first two
  -- tracks, then bars 3 and 4 of all three.
  local status = { rows = { 11, 11 }, cols = { 1, 64 } }
  T.keys("gg0llv2l")
  expect_screen("selection_time", 80, 12, status)
  T.keys("<Esc>gg0llVj")
  expect_screen("selection_tracks", 80, 12, status)
  T.keys("<Esc>gg0ll<C-v>2j2l")
  expect_screen("selection_block", 80, 12, status)
  T.keys("<Esc>")
end)

test("a clip's controller moves show as a curve on its name row, and a group with linked faders has a mark", function()
  fresh()
  paw.cmd("view.only")
  paw.opt.zoom, paw.opt.track_height = 1, 3
  local synth = paw.add_track({ name = "synth" })
  local clip =
    synth:add_clip({ name = "pad", start = 0, length = 16, notes = { { pitch = 60, start = 0, length = 16 } } })
  -- The mod wheel rises from beat 6, is up at beat 10, and falls at 14.
  clip:set_controls({
    { start = 6, type = "cc", number = 1, value = 0.25 },
    { start = 8, type = "cc", number = 1, value = 0.5 },
    { start = 10, type = "cc", number = 1, value = 1 },
    { start = 14, type = "cc", number = 1, value = 0 },
  })
  paw.groups.link(paw.groups.make({ synth }, "band"), true)
  api.undo_checkpoint()
  paw.flush()
  T.keys("gg0")
  paw.ui.message = nil
  expect_screen("controller_moves", 60, 16, { rows = { 2, 7 }, cols = { 1, 33 } })
end)

test("a looped clip's repeats and an audio clip's warp markers leave each cell its notes or sound", function()
  fresh()
  paw.cmd("view.only")
  paw.opt.zoom, paw.opt.track_height = 2, 4
  -- A beat that repeats each bar, a note on the first beat of each repeat.
  local drums = paw.add_track({ name = "drums" })
  local beat = drums:add_clip({
    name = "beat",
    start = 0,
    length = 4,
    notes = { { pitch = 36, start = 0, length = 1 }, { pitch = 38, start = 2, length = 1 } },
  })
  paw.stretch.loop(beat.id, true)
  beat.length = 12
  -- Sound that is loud on each beat, with a warp marker on beat 2.
  local voice = paw.add_track({ name = "voice" })
  local vox = voice:add_clip({ name = "vox", file = stepped_wave("beats", 4, { 0.9, 0.05 }), start = 0 })
  vox.stretch_mode = "tonal"
  paw.stretch.warp_add(vox.id, 2)
  -- The clip plays through the stretcher, which makes its sound first.
  paw.flush()
  T.until_(function() return not api.clip_get(vox.id).stretching end, "the clip's sound is made")
  api.undo_checkpoint()
  paw.flush()
  T.keys("gg0")
  paw.ui.message = nil
  expect_screen("repeats_and_warps", 60, 16, { rows = { 2, 9 }, cols = { 15, 47 } })
end)
