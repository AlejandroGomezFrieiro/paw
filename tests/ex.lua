-- Tests of Ex: ranges over time and tracks, and the commands that take
-- them (`:5,8d`, `:%s/c4/d4/g`, `:g/vel<20/d`, `:t* volume -=3`), with the
-- live preview, confirming each change, and undo. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local test, eq, fails, keys = T.test, T.eq, T.fails, T.keys
local api = paw.api
local ex = paw.ex

--- Track T with clips a, b, c (bars 1 to 3, notes C4 D♭4 D4 E♭4 on the
--- beats of each), and track Drums with clip d over bars 1 and 2.
local function song()
  local t = T.three_clips()
  -- What a line opens to show a match (the piano roll) is closed again.
  T.after(function()
    paw.keymap.feed("<Esc><Esc>")
    paw.ui.views:get("pianoroll").clip_id = nil
    paw.ui.hide("pianoroll")
    paw.ui.focus("arrange")
    paw.opt.gdefault = false
  end)
  local drums = paw.add_track({ name = "Drums" })
  drums:add_clip({
    name = "d",
    start = 0,
    length = 8,
    notes = { { 36, 0, 1 }, { 38, 1, 1, 30 }, { 36, 4, 1, 120 }, { 38, 5, 1 } },
  })
  paw.cursor.set_track(t)
  api.undo_checkpoint()
  return t, drums
end

--- Run a line as typed after `:`, as one turn.
local function run(line)
  paw.commands.exec(line)
  api.undo_checkpoint()
end

--- The name of the undo step the project is at.
local function step_name()
  local tree, at = api.undo_tree(), api.undo_current()
  for _, s in ipairs(tree.states) do
    if s.id == at then return s.label end
  end
end

local function pitches(clip)
  local out = {}
  for _, n in ipairs(clip:notes()) do
    out[#out + 1] = n.pitch
  end
  return table.concat(out, " ")
end

test("ex: ranges name bars, beats, the cursor, the end, marks and offsets", function()
  song()
  local r = ex.range("5,8d")
  eq(
    r.from .. "-" .. r.to,
    paw.time.bar_start(5) .. "-" .. paw.time.bar_start(9),
    "5,8 is bars 5 to 8, the end of 8 included"
  )
  r = ex.range("2.3,2.4y")
  eq(r.from .. "-" .. r.to, "6-8", "2.3,2.4 is beats 3 and 4 of bar 2")
  paw.cursor.set_beat(5)
  r = ex.range(".,.+1d")
  eq(r.from .. "-" .. r.to, "4-12", "`.` is the cursor's bar, `.+1` the next")
  r = ex.range("%d")
  eq(r.from .. "-" .. r.to, "0-12", "% is the whole song, to the end of its last bar")
  r = ex.range("$d")
  eq(r.from, 8, "$ is the last bar")
  paw.cursor.set_beat(2)
  paw.keymap.mark("a")
  paw.cursor.set_beat(9)
  paw.keymap.mark("b")
  r = ex.range("'a,'bd")
  eq(r.from .. "-" .. r.to, "2-9", "from mark a up to mark b, exactly")
  r = ex.range("'ad")
  eq(r.from .. "-" .. r.to, "0-4", "a mark alone stands for its bar, as for a line in Vim")
  local _, rest, err = ex.range("'qd")
  eq(rest, nil, "an unset mark names nothing")
  eq(err:find("mark q is not set", 1, true) ~= nil, true, "and says which: " .. err)
  _, _, err = ex.range("8,5d")
  eq(err:find("`8,5`", 1, true) ~= nil, true, "a backwards range names itself: " .. err)
  _, _, err = ex.range("3.9d")
  eq(err:find("no beat 9", 1, true) ~= nil, true, "a beat a bar does not have: " .. err)
  eq(ex.range("track.mute"), nil, "a command's name is no range")
  eq(select(2, ex.range("tempo 120")), "tempo 120", "nor is a name that starts with t")
end)

test("ex: ranges of tracks by number, name, all of them and the cursor's, and with time", function()
  local t, drums = song()
  local r = ex.range("t2 mute")
  eq(#r.tracks == 1 and r.tracks[1], drums.id, "t2 is the second track")
  r = ex.range("t1,t2 mute")
  eq(#r.tracks, 2, "t1,t2 both")
  eq(#ex.range("t1,2 mute").tracks, 2, "and so is t1,2")
  eq(#ex.range("t* mute").tracks, 2, "t* every track")
  r = ex.range("t/dru/ solo")
  eq(r.tracks[1], drums.id, "t/dru/ the tracks whose names hold it")
  r = ex.range("t. mute")
  eq(r.tracks[1], t.id, "t. the cursor's track")
  r = ex.range("t2 1,2d")
  eq(r.tracks[1] .. " " .. r.from .. "-" .. r.to, drums.id .. " 0-8", "tracks then time: that time on those tracks")
  local _, _, err = ex.range("t5 mute")
  eq(err:find("`t5`: there are 2 tracks", 1, true) ~= nil, true, err)
  _, _, err = ex.range("t/Bass/ mute")
  eq(err:find("no track's name holds `Bass`", 1, true) ~= nil, true, err)
end)

test("ex: d empties a range, d! takes the time out, and each line is one undo step named after it", function()
  local t, drums = song()
  keys(":2d")
  keys("<CR>")
  eq(T.layout(t), "a@0+4 c@8+4", ":2d empties bar 2 of every track")
  eq(T.layout(drums), "d@0+4", "the drum clip is cut there")
  eq(step_name(), ":2d", "one undo step, named after the line")
  eq(paw.keymap.getreg().kind, "range", "what was there is in the register")
  paw.undo()
  eq(T.layout(t), "a@0+4 b@4+4 c@8+4", "undone at once")
  run("2d!")
  eq(T.layout(t), "a@0+4 c@4+4", ":2d! closes the gap")
  paw.undo()
  run("t2 2d")
  eq(T.layout(t) .. " | " .. T.layout(drums), "a@0+4 b@4+4 c@8+4 | d@0+4", ":t2 2d only on track 2")
  paw.undo()
  run("t2d")
  eq(#paw.tracks(), 1, ":t2d deletes the track itself")
  eq(paw.keymap.getreg().kind, "tracks", "into the register as a track")
end)

test("ex: co copies and m moves a range of bars, over what is there or making room", function()
  local t = song()
  run("t1 1co 3")
  eq(T.layout(t), "a@0+4 b@4+4 a@8+4", ":1co 3 copies bar 1 over bar 3")
  paw.undo()
  run("t1 1co! 3")
  eq(T.layout(t), "a@0+4 b@4+4 a@8+4 c@12+4", "co! makes room")
  paw.undo()
  run("t1 1m 4")
  eq(T.layout(t), "b@4+4 c@8+4 a@12+4", ":1m 4 moves it")
  paw.undo()
  run("t1 1m! 4")
  eq(T.layout(t), "b@0+4 c@4+4 a@8+4", "m! closes the gap it leaves and makes room where it goes")
  fails(function() paw.commands.exec("1co") end, "needs a place")
end)

test("ex: :s changes notes that match, the first of each bar, or all with g", function()
  local t = song()
  local a = t:clips()[1]
  run("%s/c4/d4/")
  eq(pitches(a), "62 61 62 63", "C4 becomes D4")
  eq(step_name(), ":%s/c4/d4/", "named after the line")
  paw.undo()
  a:add_note({ pitch = 60, start = 2.5, length = 0.5 })
  api.undo_checkpoint()
  run("1s/c4/d4/")
  eq(pitches(a):gsub(" ", ","), "62,61,62,60,63", "without g only the first in the bar")
  paw.undo()
  run("1s/c4/d4/g")
  eq(pitches(a):gsub(" ", ","), "62,61,62,62,63", "with g every one")
  paw.undo()
  paw.opt.gdefault = true
  run("1s/c4/d4/")
  eq(pitches(a):gsub(" ", ","), "62,61,62,62,63", "gdefault turns g round")
  paw.undo()
  paw.opt.gdefault = false
  run("%s/c/e/g")
  eq(pitches(a):gsub(" ", ","), "64,61,62,64,63", "a pitch without an octave keeps the note's")
  paw.undo()
  run("%s/c4|d4/+12/g")
  eq(pitches(a):gsub(" ", ","), "72,61,74,72,63", "either of two, an octave up")
end)

test("ex: :s sets velocity and length by field, and an empty replacement removes", function()
  local _, drums = song()
  local d = drums:clips()[1]
  run("%s/vel>100/vel=90/g")
  local vels = {}
  for _, n in ipairs(d:notes()) do
    vels[#vels + 1] = n.velocity
  end
  eq(vels[3], 90, "vel>100 set to 90")
  paw.undo()
  run("%s/vel<40/vel+20 len*2/g")
  local n = d:notes()[2]
  eq(n.velocity .. " " .. n.length, "50 2", "a step and a scale")
  paw.undo()
  run("%s/vel<40//g")
  eq(#d:notes(), 3, "nothing after the pattern removes what matched")
  paw.undo()
  run("%s#len>=1 vel<40#len=1/8#g")
  eq(d:notes()[2].length, 0.5, "any delimiter, so that `/` can be in the pattern")
  paw.undo()
  fails(function() paw.commands.exec("%s/vel>>3/vel=1/") end, "vel>>3")
  fails(function() paw.commands.exec("%s/velo>3/vel=1/") end, "velo>3")
  fails(function() paw.commands.exec("%s/c4/name:x/") end, "sets clips, but the pattern matches notes")
end)

test("ex: :s renames clips by the part of the name that matched", function()
  local t = song()
  t:clips()[2].name = "Verse 2"
  api.undo_checkpoint()
  run("%s/name:verse/name:Chorus/g")
  eq(t:clips()[2].name, "Chorus 2", "the matched part is replaced")
  paw.undo()
  run("%s/name:verse/name=Bridge/g")
  eq(t:clips()[2].name, "Bridge", "= sets the whole name")
end)

test("ex: :g runs a command on every match, :v on the others, and with none fills the quickfix list", function()
  local t, drums = song()
  local d = drums:clips()[1]
  run("g/vel<40/d")
  eq(#d:notes(), 3, ":g/vel<40/d deletes the quiet note")
  eq(step_name(), ":g/vel<40/d", "one undo step")
  paw.undo()
  run("t2 v/c2/d")
  eq(pitches(d), "36 36", ":v deletes what does not match")
  paw.undo()
  run("g/name:b/mute")
  eq(T.layout(t), "a@0+4 b@4+4m c@8+4", ":g/name:b/mute mutes the clip")
  paw.undo()
  run("g/c4/")
  local list = paw.qf.current()
  eq(#list.entries, 3, "three C4s in the quickfix list")
  eq(list.title, ":g/c4/", "titled by the line")
  run("cdo s/*/vel=10/")
  local low = 0
  for _, c in ipairs(t:clips()) do
    for _, n in ipairs(c:notes()) do
      if n.velocity == 10 then low = low + 1 end
    end
  end
  eq(low, 3, ":cdo runs an Ex line on each entry")
end)

test("ex: track commands take ranges of tracks", function()
  local t, drums = song()
  run("t* volume -=3")
  eq(t.volume .. " " .. drums.volume, "-3 -3", ":t* volume -=3 steps every track down")
  run("t2 volume -12")
  eq(drums.volume, -12, "a number sets it")
  run("t2 volume =-11")
  eq(drums.volume, -11, "= sets it too")
  run("t/dru/ solo")
  eq(drums.solo, true, "solo by name")
  run("t1,t2 mute")
  eq(tostring(t.mute) .. tostring(drums.mute), "truetrue", "mute both")
  run("t* mute!")
  eq(tostring(t.mute), "false", "mute! switches")
  run("t2 pan =-0.5")
  eq(drums.pan, -0.5, "pan")
  run("2 mute")
  eq(T.layout(t), "a@0+4 b@4+4m c@8+4", "a stretch of time mutes the clips in it")
  fails(function() paw.commands.exec("2volume -3") end, "takes tracks")
end)

test("ex: transpose, quantize, > and j work on ranges", function()
  local t = song()
  run("1transpose 12")
  eq(pitches(t:clips()[1]), "72 73 74 75", "bar 1 an octave up")
  eq(pitches(t:clips()[2]), "60 61 62 63", "bar 2 as it was")
  local a = t:clips()[1]
  a:set_note(1, { start = 0.1 })
  api.undo_checkpoint()
  run("%quantize")
  eq(a:notes()[1].start, 0, "back on the grid")
  run("t1 2>")
  eq(T.layout(t), "a@0+4 b@5+4 c@8+4", ":2> moves the clip a grid step later")
  run("t1 2<<")
  eq(T.layout(t), "a@0+4 b@3+4 c@8+4", "<< two earlier")
  paw.undo()
  paw.undo()
  run("t1 1,3j")
  eq(#t:clips(), 1, ":1,3j joins them")
end)

test("ex: :quantize moves the notes that play in its bars, and says so when they are on the grid", function()
  local t = song()
  local a, c = t:clips()[1], t:clips()[3]
  -- Clip a plays bar 1 only: a trim of it hides a note at a time of bar 3.
  a:add_note({ pitch = 72, start = 8.3, length = 0.5 })
  api.undo_checkpoint()
  local function hidden() return a:notes()[#a:notes()].start end
  local steps = #api.undo_tree().states

  keys(":3quantize 1/4<CR>")
  local said = paw.ui.messages[#paw.ui.messages].text
  eq(said, "4 notes on the grid of 1 beats already", "nothing moves")
  eq(#api.undo_tree().states, steps, "and nothing is an undo step")

  c:set_note(2, { start = 1.3 })
  api.undo_checkpoint()
  keys(":3quantize 1/4<CR>")
  eq(c:notes()[2].start, 1, "the note of bar 3 off the grid is on it")
  eq(hidden(), 8.3, "the note that clip a hides is not in bar 3")
  keys("u")
  eq(c:notes()[2].start, 1.3, "u gives it back")
end)

test("ex: :%quantize moves the notes of several clips, and one u gives them all back", function()
  local t = song()
  local a, b = t:clips()[1], t:clips()[2]
  a:set_note(2, { start = 1.1 })
  b:set_note(4, { start = 3.2 })
  api.undo_checkpoint()
  keys(":%quantize 1/16<CR>")
  eq(a:notes()[2].start, 1, "the note of clip a is on the grid")
  eq(b:notes()[4].start, 3.25, "and the note of clip b")
  keys("u")
  eq(a:notes()[2].start, 1.1, "u gives back the note of clip a")
  eq(b:notes()[4].start, 3.2, "and the note of clip b")
end)

test("ex: the notes of a range come in the order of the song: by time, then pitch, then track", function()
  local _, drums = song()
  -- A note of the drums at the time and pitch of one of track T.
  drums:clips()[1]:add_note({ pitch = 62, start = 2, length = 1 })
  local got = {}
  for _, item in ipairs(ex.items(ex.range("1,2"), "note")) do
    got[#got + 1] = string.format("%s:%d@%g", paw.api.track_get(item.track).name, item.note.pitch, item.at)
  end
  eq(
    table.concat(got, " "),
    "Drums:36@0 T:60@0 Drums:38@1 T:61@1 T:62@2 Drums:62@2 T:63@3 "
      .. "Drums:36@4 T:60@4 Drums:38@5 T:61@5 T:62@6 T:63@7",
    "in order across tracks and clips"
  )
end)

test("paw.notes.snap gives the start that paw.notes.quantize gives a note", function()
  -- { start, options, the start on the grid }
  local cases = {
    { 1.1, { grid = 0.25 }, 1 },
    { 0.9, { grid = 0.25, offset = 0.1 }, 0.9 },
    { 1.1, { grid = 0.25, strength = 0.5 }, 1.05 },
    { 0.45, { grid = 0.5, swing = 0.5 }, 0.75 },
    { 3.95, { grid = 0.25, within = 4 }, 3.75 },
    { -0.3, { grid = 0.25 }, 0 },
  }
  for _, case in ipairs(cases) do
    local start, opts, want = case[1], case[2], case[3]
    local what = paw.inspect(opts) .. " from " .. start
    T.near(paw.notes.snap(start, opts), want, 1e-9, what)
    local moved = paw.notes.quantize({ { pitch = 60, start = start, length = 0.1, velocity = 100 } }, opts)
    T.near(moved[1].start, want, 1e-9, "quantize, " .. what)
  end
end)

test("ex: normal runs keys at each bar, track or match", function()
  song()
  local seen = {}
  paw.keymap.set(
    "Q",
    function() seen[#seen + 1] = paw.cursor.track().name .. "@" .. paw.cursor.beat end,
    { view = "arrange" }
  )
  run("t1 1,3normal Q")
  eq(table.concat(seen, " "), "T@0 T@4 T@8", "at the start of each bar")
  seen = {}
  run("t* normal Q")
  eq(#seen, 2, "at each track")
  eq(seen[2]:match("^Drums") ~= nil, true, "the cursor on each")
  seen = {}
  run("g/name:a|name:c/normal Q")
  eq(table.concat(seen, " "), "T@0 T@8", "at each clip that matches")
  paw.keymap.del("Q", { view = "arrange" })
end)

test("ex: in the piano roll a range is of its clip's notes, and '<,'> of the notes selected", function()
  local t, drums = song()
  paw.cursor.set_track(t)
  paw.cursor.set_beat(4)
  keys("<CR>")
  eq(paw.ui.focused, "pianoroll", "the roll is open on clip b")
  run("%s/c4/d4/g")
  eq(pitches(t:clips()[2]), "62 61 62 63", "its C4 changed")
  eq(pitches(t:clips()[1]), "60 61 62 63", "the others' did not")
  eq(pitches(drums:clips()[1]), "36 38 36 38", "nor another track's")
  paw.undo()
  run(".d")
  eq(#t:clips()[2]:notes(), 0, ":.d deletes the notes of the cursor's bar")
  eq(paw.keymap.getreg().kind, "notes", "into the register as notes")
  paw.undo()
  run("mute")
  eq(api.track_get(t.id).mute, true, ":mute mutes the track of the clip it edits")
  paw.undo()
  paw.ui.views:get("pianoroll"):set(61, 1)
  keys("<C-v>k5l<Esc>")
  run("'<,'>d")
  eq(pitches(t:clips()[2]), "60 63", "'<,'> takes the pitches and beats selected")
  keys("<Esc>")
end)

test("ex: typing a line shows what it matches and would make, and Escape changes nothing", function()
  local t = song()
  local cmdline = require("paw.views.cmdline")
  keys(":%s/c4/d4/g")
  local state = cmdline.state()
  eq(state.note, "3 notes match", "the count on the command line")
  local shown = ex.shown()
  eq(#shown.matches, 3, "the views are told the matches")
  local first = shown.notes[t:clips()[1].id]
  local change
  for _, m in pairs(first) do
    change = m.change
  end
  eq(change.pitch, 62, "and what each becomes")
  keys("<Esc>")
  eq(ex.shown(), nil, "Escape takes it away")
  eq(pitches(t:clips()[1]), "60 61 62 63", "and nothing changed")
  keys(":2,1d")
  eq(cmdline.state().note_level, "error", "a bad range is said while typing")
  eq(cmdline.state().note:find("`2,1`", 1, true) ~= nil, true, cmdline.state().note)
  keys("<Esc>:t1,")
  eq(cmdline.state().note, nil, "a range typed up to its comma says nothing yet")
  keys("t2")
  eq(cmdline.state().note_level ~= "error", true, "and is a range once finished")
  keys("<Esc>:5,")
  eq(cmdline.state().note, nil, "nor does a range of bars")
  keys("<Esc>:t2 1,2")
  eq(cmdline.state().note, "bars 1–2 on Drums", "a range says what it covers")
  local lines = api.ui_snapshot(100, 30)
  eq(lines[#lines]:find("bars 1–2 on Drums", 1, true) ~= nil, true, "on the bottom row: " .. lines[#lines])
  keys("<Esc>")
end)

test("ex: :s with c asks about each match, and what was said yes to is one undo step", function()
  local t = song()
  keys(":%s/c4/d4/gc<CR>")
  local cmdline = require("paw.views.cmdline")
  eq(cmdline.state().prompt:find("1 of 3", 1, true) ~= nil, true, "asks about the first: " .. cmdline.state().prompt)
  eq(ex.shown().current ~= nil, true, "which the views show")
  keys("y")
  keys("n")
  keys("y")
  eq(
    pitches(t:clips()[1]) .. "|" .. pitches(t:clips()[2]) .. "|" .. pitches(t:clips()[3]),
    "62 61 62 63|60 61 62 63|62 61 62 63",
    "yes, no, yes"
  )
  eq(step_name(), ":%s/c4/d4/gc", "as one step")
  paw.undo()
  eq(pitches(t:clips()[3]), "60 61 62 63", "undone together")
  keys(":%s/c4/d4/gc<CR>")
  keys("<Esc>")
  eq(pitches(t:clips()[1]), "60 61 62 63", "Escape at once changes nothing")
  keys(":%s/c4/d4/gc<CR>")
  keys("a")
  eq(pitches(t:clips()[3]), "62 61 62 63", "a: this and all the rest")
end)

test("ex: completion offers marks, tracks and pattern fields", function()
  song()
  paw.cursor.set_beat(4)
  paw.keymap.mark("a")
  local labels = {}
  for _, c in ipairs(paw.commands.complete("'")) do
    labels[#labels + 1] = c.label
  end
  eq(
    table.concat(labels, " "):match("^'<,'> 'a") ~= nil,
    true,
    "the selection and the marks after ': " .. table.concat(labels, " ")
  )
  local c = paw.commands.complete("t/dr")
  eq(c[1] and c[1].text, "t/Drums/ ", "tracks after t/")
  c = paw.commands.complete("%s/ve")
  eq(c[1] and c[1].text, "%s/vel", "fields in a pattern")
  local found
  for _, entry in ipairs(paw.commands.complete("%tra")) do
    if entry.text == "%transpose" then found = true end
  end
  eq(found, true, "a command after a range")
end)

test("ex: an extension adds a pattern field and a command that takes a range", function()
  local t = song()
  ex.field("lyric", {
    level = "note",
    type = "text",
    get = function(item) return item.note.meta and item.note.meta.lyric end,
    set = function(item, value, change) change.meta = paw.util.merge(item.note.meta or {}, { lyric = value }) end,
  })
  run("1s/c4/lyric=la/")
  eq(t:clips()[1]:notes()[1].meta.lyric, "la", "a field of its own, set")
  run("g/lyric:la/transpose 1")
  eq(t:clips()[1]:notes()[1].pitch, 61, "and matched")
  local counted
  paw.command("test.count", function(ctx) counted = #ex.items(ctx.range, "note") end, { range = true })
  run("t1 2,3test.count")
  eq(counted, 8, "a command with a range finds the notes in it")
  ex.fields:remove("lyric")
end)

test("ex: a clip whatever an extension keeps with it is MIDI, edited as any other", function()
  local t = song()
  -- A clip an older notation kept a score with: its notes are still the clip's.
  local clip = t:clips()[1]
  clip.meta = { score = { measures = {} } }
  local before, c4 = #clip:notes(), 0
  for _, n in ipairs(clip:notes()) do
    if n.pitch == 60 then c4 = c4 + 1 end
  end
  eq(c4 > 0, true, "the clip has C4s")
  paw.commands.exec("%s/c4/d4/g")
  c4 = 0
  for _, n in ipairs(clip:notes()) do
    if n.pitch == 60 then c4 = c4 + 1 end
  end
  eq(c4, 0, "every C4 is a D4 now")
  eq(#clip:notes(), before, "and no note is lost")
end)

test("ex: in a text buffer a line's ranges are lines, as the buffer reads them", function()
  local t = song()
  local L = paw.layout
  local before = L.capture()
  T.after(function()
    for _, buf in ipairs(L.buffers_list()) do
      if buf.type == "textbuf" then L.buf_delete(buf) end
    end
    L.restore(before)
  end)
  keys(":e paw://tracks<CR>")
  local tb = require("paw.textbuf")
  keys(":2d<CR>")
  eq(#tb.buf().state.text.lines, 1, ":2d deletes the second line of the buffer")
  eq(T.layout(t), "a@0+4 b@4+4 c@8+4", "not bar 2 of the song")
  keys(":%s/Drums/Kit/<CR>")
  eq(api.track_get(api.track_list()[2]).name, "Drums", "and :s edits the text, not the notes, until :w")
end)
