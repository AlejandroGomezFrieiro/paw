-- Modal editing tests.
local T = ...
local test, eq, fresh, tone = T.test, T.eq, T.fresh, T.tone
local scratch, three_clips, layout, melody, keys = T.scratch, T.three_clips, T.layout, T.melody, T.keys
local paw = require("paw")
local api = paw.api

test("an operator takes a motion, a text object or a count", function()
  local t = three_clips()
  keys("dw")
  eq(layout(t), "b@4+4 c@8+4", "dw deletes up to the next clip")
  paw.undo()
  keys("ld2l")
  eq(layout(t), "a@0+1 a@3+1 b@4+4 c@8+4", "d2l cuts two beats out of a clip")
  eq(melody(t:clips()[1]) .. " | " .. melody(t:clips()[2]), "60@0+1 | 63@0+1", "the notes stay with their halves")
  eq(paw.cursor.beat, 1, "the cursor is where the gap starts")
  paw.undo()
  keys("d2ib")
  eq(layout(t), "c@8+4", "d2ib deletes two bars")
  paw.undo()
  keys("wd$")
  eq(layout(t), "a@0+4", "d$ deletes to the end of the track")
  paw.undo()
  keys("0dic")
  eq(layout(t), "b@4+4 c@8+4", "dic deletes the clip")
  keys("P")
  eq(layout(t), "a@0+4 b@4+4 c@8+4", "P puts it back at the cursor")
  eq(melody(t:clips()[1]), "60@0+1 61@1+1 62@2+1 63@3+1", "with its notes")
  keys("d3d")
  eq(#paw.tracks(), 0, "d3d takes whole tracks, as many as there are")
  paw.undo()
  keys("dx")
  eq(paw.keymap.mode .. layout(t), "na@0+4 b@4+4 c@8+4", "a key that is no motion calls the operator off")
  keys("d<Esc>l")
  eq(paw.cursor.beat, 1, "and so does Escape")
end)

test("yank and paste work on clips, stretches of time and whole tracks", function()
  local t = three_clips()
  keys("yicp")
  eq(layout(t), "a@0+4 a@4+4 c@8+4", "p puts the yanked clip after the one under the cursor, over what was there")
  eq(paw.cursor.beat, 4, "and the cursor on it")
  keys("p")
  eq(layout(t), "a@0+4 a@4+4 a@8+4", "p again carries on")
  keys("2p")
  eq(layout(t), "a@0+4 a@4+4 a@8+4 a@12+4 a@16+4", "a count pastes that many times")
  eq(paw.cursor.beat, 16, "the cursor is on the last copy")
  paw.undo()
  paw.undo()
  paw.undo()
  eq(layout(t), "a@0+4 b@4+4 c@8+4", "each paste is one undo step")

  -- A named register is not disturbed by what is deleted later.
  paw.cursor.set_beat(0)
  keys('"qyicwdic')
  eq(layout(t), "a@0+4 c@8+4", "b is gone")
  keys('"qP')
  eq(layout(t), "a@0+4 a@4+4 c@8+4", 'and "q still held a')
  keys('"_dicP')
  eq(layout(t), "a@0+4 b@4+4 c@8+4", 'deleting into "_ leaves the unnamed register alone')

  -- Whole tracks, with their devices, clips and automation.
  t:automate("volume"):set_points({ { 0, -12 }, { 4, 0 } })
  api.undo_checkpoint()
  keys("yyp")
  eq(#paw.tracks(), 2, "yyp duplicates the track")
  local copy = paw.cursor.track()
  eq(paw.cursor.index(), 2, "below, with the cursor on it")
  eq(layout(copy), layout(t), "with its clips")
  eq(copy:devices()[1].params.cutoff, 900, "its devices as they were set")
  eq(#copy:lane("volume"):points(), 2, "and its automation")
  keys("dd")
  eq(#paw.tracks(), 1, "dd removes it")
  keys("P")
  eq(paw.tracks()[1].id ~= t.id and layout(paw.tracks()[1]), layout(t), "P puts it back above")

  -- A stretch of time across tracks.
  paw.cursor.set_track(paw.tracks()[1])
  paw.cursor.set_beat(4)
  keys("vjWy")
  local value = paw.keymap.getreg()
  eq(value.kind .. value.length .. #value.rows, "range42", "v with j selects the same stretch on two tracks")
  keys("3Wk")
  keys("p")
  eq(
    layout(paw.tracks()[1]) .. " | " .. layout(paw.tracks()[2]),
    "a@0+4 b@4+4 c@8+4 b@16+4 | a@0+4 b@4+4 c@8+4 b@16+4",
    "and it is pasted on both"
  )

  paw.opt.ripple = true
  paw.cursor.set_beat(0)
  keys("dic")
  eq(layout(paw.tracks()[1]), "b@0+4 c@4+4 b@12+4", "with ripple, deleting closes the gap")
  keys("P")
  eq(layout(paw.tracks()[1]), "a@0+4 b@4+4 c@8+4 b@16+4", "and pasting makes room")
  paw.opt.ripple = false
end)

test("visual mode selects time, tracks, and what a text object names", function()
  local t = three_clips()
  local other = paw.add_track({ name = "U" })
  other:add_clip({ name = "u", start = 0, length = 12 })
  api.undo_checkpoint()
  keys("v")
  local sel = paw.keymap.selection()
  eq(paw.keymap.mode .. sel.c0 .. "-" .. sel.c1, "x0-1", "v starts with one grid step")
  keys("WW")
  sel = paw.keymap.selection()
  eq(sel.c0 .. "-" .. sel.c1 .. " rows " .. sel.r0 .. "-" .. sel.r1, "0-8 rows 1-1", "motions stretch it")
  keys("j")
  eq(paw.keymap.selection().r1, 2, "onto other tracks too")
  keys("o")
  eq(paw.cursor.index() .. "@" .. paw.cursor.beat, "1@0", "o goes to the other end")
  keys("d")
  eq(paw.keymap.mode, "n", "an operator ends visual mode")
  eq(layout(t) .. " | " .. layout(other), "c@8+4 | u@8+4", "and acts on the selection")
  paw.undo()

  keys("gv")
  eq(paw.keymap.selection().c1, 8, "gv selects it again")
  keys("<Esc>wvic")
  sel = paw.keymap.selection()
  eq(sel.c0 .. "-" .. sel.c1, "4-8", "a text object becomes the selection")
  keys("~")
  eq(layout(t), "a@0+4 b@4+4m c@8+4", "~ mutes the selected clips")
  keys("gv~")
  eq(layout(t), "a@0+4 b@4+4 c@8+4", "and unmutes them")

  keys("0Vjgc")
  eq(tostring(t.mute) .. tostring(other.mute), "truetrue", "V selects whole tracks; gc mutes them")
  keys("gcc")
  eq(tostring(t.mute) .. tostring(other.mute), "falsetrue", "gcc is one track")
  keys("jgcck")

  keys("vee<C-a>")
  eq(
    melody(t:clips()[1]):sub(1, 6) .. melody(t:clips()[3]):sub(1, 6),
    "61@0+160@0+1",
    "<C-a> transposes the selected clips"
  )
  keys("0veJ")
  eq(layout(t), "a@0+4 b@4+4 c@8+4", "J needs two clips")
  keys("veeeJ")
  eq(layout(t), "a@0+12", "J joins the selected clips")
  eq(#t:clips()[1]:notes(), 12, "with all their notes")
  keys("v")
  paw.ui.focus("mixer")
  eq(paw.keymap.mode, "n", "moving to another view ends visual mode")
  paw.ui.hide("mixer")
  paw.ui.focus("arrange")
end)

test("the other operators shift, quantize, loop and change", function()
  local t = three_clips()
  keys(">ic")
  eq(
    layout(t) .. " cursor " .. paw.cursor.beat,
    "a@1+4 b@4+4 c@8+4 cursor 1",
    "> moves the clip a grid step, and the cursor with it"
  )
  keys("u")
  keys("3>>")
  eq(layout(t), "a@1+4 b@5+4 c@9+4", ">> moves every clip of the track")
  keys("<lt><lt>")
  eq(layout(t), "a@0+4 b@4+4 c@8+4", "<< moves them back")
  t:clips()[2].start = 4.4
  t:clips()[2]:set_notes({ { pitch = 60, start = 0.1, length = 0.5 } })
  api.undo_checkpoint()
  keys("==")
  eq(
    layout(t) .. " " .. melody(t:clips()[2]),
    "a@0+4 b@4+4 c@8+4 60@0+0.5",
    "== snaps clips and their notes to the grid"
  )
  keys("wglic")
  eq(
    paw.transport.loop_start .. "-" .. paw.transport.loop_end .. tostring(paw.transport.loop_enabled),
    "4-8true",
    "gl loops what the motion covers"
  )
  paw.transport.loop_enabled = false
  keys("cic")
  eq(paw.ui.focused .. paw.keymap.mode, "pianorolli", "c opens a fresh clip for entering notes")
  eq(layout(t), "a@0+4 b@4+4 c@8+4", "in place of the old one, under its name")
  eq(#t:clips()[2]:notes(), 0, "and empty")
  keys("<Esc>")
  paw.ui.focus("arrange")
  paw.cursor.set_beat(0)
  keys("J")
  eq(layout(t), "a@0+8 c@8+4", "J joins the clip with the next")
  keys("S")
  eq(layout(t), "a@0+8 c@8+4", "S at the start of a clip does nothing")
  keys("2lS")
  eq(layout(t), "a@0+2 a@2+6 c@8+4", "S splits at the cursor")
end)

test("the dot, macros, marks, jumps and search repeat and find things", function()
  local t = three_clips()
  keys("x")
  keys("w.")
  eq(layout(t), "c@8+4", ". repeats the last change")
  paw.undo()
  paw.undo()
  keys("0L")
  keys("3.")
  eq(layout(t), "a@4+4 b@4+4 c@8+4", "a count on . replaces the one it had")
  paw.undo()
  paw.undo()
  paw.cursor.set_beat(0)
  keys("jk.")
  eq(layout(t), "a@1+4 b@4+4 c@8+4", "moving the cursor is not a change: . still repeats the one before")
  paw.undo()

  keys("0qqxwq")
  eq(layout(t) .. paw.keymap.getreg("q").keys, "b@4+4 c@8+4xw", "q records keys into a register")
  keys("2@q")
  eq(layout(t), "", "@ plays them, with a count")
  keys("@@")
  eq(layout(t) .. paw.keymap.mode, "n", "@@ plays the last one again, here with nothing left to delete")
  paw.undo()
  paw.undo()
  eq(layout(t), "a@0+4 b@4+4 c@8+4", "a macro is undone in one step")
  keys(":track.volume by=-2<CR>")
  keys("@:")
  eq(t.volume, -4, "@: runs the last command line again")

  paw.cursor.set_beat(0)
  local other = paw.add_track({ name = "Other" })
  other:add_clip({ name = "chorus", start = 16, length = 4 })
  api.undo_checkpoint()
  keys("WmaG$")
  eq(paw.cursor.index() .. "@" .. paw.cursor.beat, "2@20", "G and $ move")
  keys("'a")
  eq(paw.cursor.index() .. "@" .. paw.cursor.beat, "1@4", "'a returns to the mark")
  keys("''")
  eq(paw.cursor.index() .. "@" .. paw.cursor.beat, "2@20", "'' goes back")
  keys("gg0")
  keys("d'a")
  eq(layout(t), "b@4+4 c@8+4", "a mark is a motion for an operator")
  paw.undo()
  keys("/chor<CR>")
  eq(paw.cursor.index() .. "@" .. paw.cursor.beat, "2@16", "/ finds a clip by name")
  keys("<C-o>")
  eq(paw.cursor.index() .. "@" .. paw.cursor.beat, "1@0", "<C-o> goes back to where the search began")
  keys("/other<CR>")
  eq(paw.cursor.index(), 2, "/ finds a track by name")
  keys("9|")
  eq(paw.cursor.beat, 32, "N| goes to a bar")
  keys(":3<CR>")
  eq(paw.cursor.beat, 8, "and so does a number on the command line")
end)

test("half-typed commands show what can follow, and are counted right", function()
  three_clips()
  paw.opt.hint_delay = 0
  paw.keymap.feed("2d3")
  eq(paw.keymap.pending(), "2d3", "what was typed so far")
  eq(paw.keymap.mode, "o", "an operator is waiting")
  local hints, title = paw.keymap.hints()
  local found = {}
  for _, hint in ipairs(hints) do
    found[hint.key] = hint.desc
  end
  eq(found.w, "Start of the next clip", "motions are offered")
  eq(found.i, "+7 more", "and the start of text objects")
  eq(title, "Delete …", "under the operator's name")
  local screen = table.concat(api.ui_snapshot(100, 30), "\n")
  eq(screen:find("Delete …", 1, true) ~= nil and screen:find("PENDING", 1, true) ~= nil, true, "on screen")
  paw.keymap.feed("l")
  eq(paw.keymap.pending() .. paw.keymap.mode, "n", "done")
  eq(layout(paw.tracks()[1]), "b@6+2 c@8+4", "2d3l deleted six beats")
  paw.keymap.feed("g")
  hints = paw.keymap.hints()
  eq(hints ~= nil and #hints > 5, true, "a prefix lists its continuations")
  paw.keymap.feed("<Esc>")
  eq(paw.keymap.hints(), nil, "Escape clears them")
  paw.opt.hint_delay = 500
  -- An operator that fails leaves normal mode behind.
  T.expect_error("boom")
  paw.keymap.operator("gz", function() error("boom") end, { view = "arrange", desc = "Fails" })
  local before = paw.ui.messages[#paw.ui.messages]
  paw.keymap.feed("gzl")
  eq(paw.keymap.mode .. paw.keymap.pending(), "n", "back to normal after an error")
  local said = paw.ui.messages[#paw.ui.messages]
  eq(said ~= before and said.text:find("boom") ~= nil, true, "which is reported")
  paw.keymap.del("gz", { view = "arrange" })
  paw.keymap.del("gz", { view = "arrange", mode = "x" })
end)

test("the piano roll has the same grammar for notes", function()
  local t = three_clips()
  local clip = t:clips()[1]
  clip:set_notes({
    { pitch = 60, start = 0, length = 0.5 },
    { pitch = 64, start = 0.5, length = 0.5 },
    { pitch = 67, start = 1, length = 1 },
    { pitch = 72, start = 1, length = 1 },
    { pitch = 60, start = 2, length = 0.5 },
    { pitch = 62, start = 3.1, length = 0.3 },
  })
  api.undo_checkpoint()
  keys("<CR>")
  local roll = paw.ui.views:get("pianoroll")
  eq(roll.pitch .. "@" .. roll.beat, "60@0", "the roll opens on the first note")
  keys("w")
  eq(roll.pitch .. "@" .. roll.beat, "64@0.5", "w goes to the next note, whatever its pitch")
  keys("e")
  eq(roll.beat, 1, "e to where it ends")
  keys("b")
  eq(roll.pitch .. "@" .. roll.beat, "64@0.5", "b back to where it starts")
  keys("0dw")
  eq(melody(clip), "64@0.5+0.5 67@1+1 72@1+1 60@2+0.5 62@3.1+0.3", "dw deletes up to the next note")
  keys("u0d4l")
  eq(melody(clip), "67@1+1 72@1+1 60@2+0.5 62@3.1+0.3", "a stretch of time takes every pitch in it")
  keys("u")
  keys("wyinp")
  eq(melody(clip):match("64@1%S+"), "64@1+0.5", "yin and p repeat the note after itself")
  keys("u")
  eq(roll.pitch, 64, "the cursor is on the note that was repeated")
  keys("0<C-v>4kWd")
  eq(melody(clip), "60@0+0.5 72@1+1 60@2+0.5 62@3.1+0.3", "a block takes only the pitches it spans, E4 to G#4 here")
  keys("u")
  roll:set(60, 0)
  keys("Vd")
  eq(melody(clip), "64@0.5+0.5 67@1+1 72@1+1 62@3.1+0.3", "V and dd take whole pitches")
  keys("u")
  keys("$")
  eq(roll.beat, 4, "$ is the end of the clip")
  keys("0=ie")
  eq(melody(clip):match("%S+$"), "62@3+0.25", "= snaps notes to the grid")
  keys("0yibWP")
  eq(#clip:notes() .. " " .. melody(clip):match("60@4%S+"), "12 60@4+0.5", "a bar pasted at the next bar")
  eq(clip.length, 8, "and the clip grew to hold it")
  keys("0ggvee")
  keys("<C-a>")
  eq(melody(clip):sub(1, 21), "61@0+0.5 65@0.5+0.5 6", "<C-a> transposes the selected notes")
  keys("/c5<CR>")
  eq(roll.pitch .. "@" .. roll.beat, "72@1", "/ finds a note by its name")
  keys("glib")
  eq(paw.transport.loop_start .. "-" .. paw.transport.loop_end, "0-4", "gl loops the bar")
  paw.transport.loop_enabled = false
  keys("<C-w>c")
  eq(paw.ui.focused, "arrange", "<C-w>c closes the roll")
end)

test("devices are cut, yanked and pasted in the device panel", function()
  local t = three_clips()
  t:add_device("delay", { mix = 0.7 })
  local other = paw.add_track({ name = "U" })
  api.undo_checkpoint()
  paw.ui.focus("devices")
  local panel = paw.ui.views:get("devices")
  panel.row = 1
  keys("yy")
  eq(paw.keymap.getreg().device.kind, "synth", "yy takes the device under the cursor")
  keys("p")
  local kinds = {}
  for i, d in ipairs(t:devices()) do
    kinds[i] = d.kind
  end
  eq(table.concat(kinds, " "), "synth synth delay", "p puts a copy after it")
  eq(t:devices()[2].params.cutoff, 900, "with its settings")
  keys("dd")
  eq(#t:devices(), 2, "dd cuts it")
  paw.cursor.set_track(other)
  keys("p")
  eq(other:devices()[1].params.cutoff, 900, "and p puts it on another track")
  paw.ui.hide("devices")
  paw.ui.focus("arrange")
end)

test("views draw without errors at several sizes", function()
  fresh()
  local t = tone("tone", 4)
  t:add_device("delay")
  for _, name in ipairs({ "mixer", "devices", "pianoroll" }) do
    paw.ui.show(name)
  end
  paw.ui.views:get("pianoroll"):edit(t:clips()[1])
  for _, size in ipairs({ { 120, 40 }, { 80, 24 }, { 30, 8 }, { 4, 2 } }) do
    local rects = paw.ui.arrange(size[1], size[2])
    local total = 0
    for _, r in ipairs(rects) do
      eq(r.x >= 0 and r.y >= 0 and r.x + r.w <= size[1] and r.y + r.h <= size[2], true, r.name .. " fits the screen")
      -- A panel drawn over the others on a narrow screen is meant to overlap.
      if r.after ~= "box" then total = total + r.w * r.h end
    end
    eq(total <= size[1] * size[2], true, "views do not overlap")
  end
  for _, name in ipairs({ "mixer", "devices", "pianoroll" }) do
    paw.ui.hide(name)
  end
  paw.ui.focus("arrange")
end)

test("the screen draws what the project holds", function()
  fresh()
  local t = tone("Lead Synth", 4)
  t:add_device("delay")
  paw.cursor.set_track(t)
  local function screen(width, height) return table.concat(api.ui_snapshot(width, height), "\n") end
  local text = screen(100, 30)
  eq(text:find("Lead Synth", 1, true) ~= nil, true, "track name is on screen")
  eq(text:find("Master", 1, true) ~= nil, true, "master track is on screen")
  eq(text:find("120 bpm", 1, true) ~= nil, true, "status line shows the tempo")
  eq(text:find("render failed", 1, true), nil, "no view failed to draw")
  paw.ui.show("devices")
  paw.ui.show("mixer")
  paw.ui.views:get("pianoroll"):edit(t:clips()[1])
  text = screen(140, 50)
  eq(text:find("cutoff", 1, true) ~= nil, true, "device panel lists parameters")
  eq(text:find("A3", 1, true) ~= nil, true, "piano roll shows note names")
  eq(text:find("traceback", 1, true), nil, "no view raised an error")
  -- Tiny screens must not raise either, and drawing garbage is collected safely.
  for _ = 1, 50 do
    screen(12, 4)
  end
  collectgarbage()
  collectgarbage()
  -- A broken view shows its error in place and leaves the others alone.
  paw.ui.view("status", { render = function() error("status is broken") end })
  text = screen(100, 30)
  eq(text:find("status is broken", 1, true) ~= nil, true, "the error is shown")
  eq(text:find("Lead Synth", 1, true) ~= nil, true, "other views still draw")
  package.loaded["paw.views.status"] = nil
  require("paw.views.status")
  for _, name in ipairs({ "mixer", "devices", "pianoroll" }) do
    paw.ui.hide(name)
  end
  paw.ui.focus("arrange")
end)

test("extensions load from a directory", function()
  local dir = scratch .. "/extensions"
  os.execute("mkdir -p '" .. dir .. "/hello/lua'")
  local function write(path, text)
    local f = assert(io.open(path, "w"))
    f:write(text)
    f:close()
  end
  write(dir .. "/hello/lua/hello_lib.lua", "return { greeting = 'hi' }")
  write(dir .. "/hello/init.lua", "paw.command('hello', function() return require('hello_lib').greeting end)")
  write(dir .. "/single.lua", "paw.command('single', function() return 'one file' end)")
  write(dir .. "/broken.lua", "error('boom')")
  paw.ext.load_dir(dir)
  eq(paw.cmd("hello"), "hi", "directory extension with a module")
  eq(paw.cmd("single"), "one file", "single-file extension")
  eq(paw.ext.loaded.broken.ok, false, "a failing extension is recorded")
  eq(paw.ext.loaded.hello.ok, true, "and does not stop the others")
end)
