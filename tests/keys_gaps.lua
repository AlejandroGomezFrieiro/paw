-- Keys that the user guide found missing or slow: fades on the clip's local
-- leader, counts before Alt-j, Alt-k and &, `[` and `]` that act at once,
-- tap tempo, and searches over the whole description of a key.
local T = ...
local advance = T.advance
local test, eq, near, fresh, keys = T.test, T.eq, T.near, T.fresh, T.keys
local api = paw.api

local function start()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
  -- The errors these tests make on purpose count as read when they end,
  -- so that the key line of the tests after them is as it always is.
  T.after(function() paw.emit("command.pre", { name = "messages", command = "messages", args = {} }) end)
end

local function message() return paw.ui.message and paw.ui.message.text or "" end

test("\\fi and \\fo fade the audio clip up to the cursor and from it; a count gives the beats", function()
  start()
  local s = {}
  for i = 1, 48000 * 4 do
    s[i] = 0.25
  end
  local file = T.write_wav(T.scratch .. "/fade-keys.wav", s)
  local t = paw.add_part({ name = "Guitar" })
  local clip = t:add_clip({ file = file, start = 0, length = 8 })
  paw.cursor.set_part(t)
  paw.cursor.set_beat(2)
  keys("<localleader>fi")
  eq(clip.fade_in, 2, "\\fi fades in from the start of the clip to the cursor")
  paw.cursor.set_beat(5)
  keys("<localleader>fo")
  eq(clip.fade_out, 3, "\\fo fades out from the cursor to the end")
  keys("1<localleader>fo")
  eq(clip.fade_out, 1, "a count is the beats")
  eq(message():find("fades out over 1 beat", 1, true) ~= nil, true, "it says what it did: " .. message())
  paw.undo()
  eq(clip.fade_out, 3, "one undo step")
  keys("<localleader>ff1 2<CR>")
  eq(clip.fade_in .. " " .. clip.fade_out, "1 2", "\\ff types both lengths")
end)

test("[ and ] act at once in the mixer and on velocity, also pressed fast, and ]x still works after them", function()
  start()
  local t = paw.add_part({ name = "A" })
  paw.cursor.set_part(t)
  paw.ui.focus("mixer")
  T.after(function()
    paw.ui.hide("mixer")
    paw.ui.focus("arrange")
  end)
  paw.keymap.feed("[")
  near(t.pan, -0.1, 1e-9, "one [ pans at once, with no wait")
  paw.keymap.feed("[[")
  near(t.pan, -0.3, 1e-9, "[ pressed fast three times is three steps, not [[")
  paw.keymap.feed("]]]")
  near(t.pan, 0, 1e-9, "and ] the same")
  paw.ui.hide("mixer")
  local c = t:add_clip({ start = 0, length = 8, notes = { { "C4", 0, 1 }, { "C4", 3, 1 } } })
  local roll = paw.ui.views:get("pianoroll")
  roll:edit(c)
  T.after(function()
    roll.clip_id = nil
    paw.ui.hide("pianoroll")
  end)
  paw.ui.focus("pianoroll")
  roll:set(60, 0)
  api.undo_checkpoint()
  paw.keymap.feed("]")
  eq(c:notes()[1].velocity, 110, "] is louder at once")
  paw.keymap.feed("]")
  eq(c:notes()[1].velocity, 120, "a second ] is louder again")
  local grids = paw.opt.grid .. " " .. paw.opt.note_grid
  paw.keymap.feed("[g")
  eq(c:notes()[1].velocity, 120, "[ then g is the grid key: the velocity change is taken back")
  eq(paw.opt.grid .. " " .. paw.opt.note_grid ~= grids, true, "and [g made the grid finer")
  paw.keymap.feed("]g")
  advance(paw.opt.timeoutlen + 100)
  eq(paw.keymap.pending(), "", "nothing is left half typed after the wait")
  paw.undo()
  eq(c:notes()[1].velocity, 110, "each press is one undo step")
end)

test("[ and ] on a selection of notes act at once, as in normal mode", function()
  start()
  local t = paw.add_part({ name = "A" })
  local c = t:add_clip({ start = 0, length = 4, notes = { { "C4", 0, 1 }, { "E4", 1, 1 } } })
  local roll = paw.ui.views:get("pianoroll")
  roll:edit(c)
  T.after(function()
    roll.clip_id = nil
    paw.ui.hide("pianoroll")
  end)
  paw.ui.focus("pianoroll")
  roll:set(60, 0)
  api.undo_checkpoint()
  paw.keymap.feed("vie]")
  eq(c:notes()[1].velocity .. " " .. c:notes()[2].velocity, "110 110", "vie ] is louder at once, with no wait for ]g")
  advance(paw.opt.timeoutlen + 100)
  paw.keymap.feed("gv[")
  eq(c:notes()[1].velocity .. " " .. c:notes()[2].velocity, "100 100", "gv [ is softer at once")
end)

test("? and Space fk search the whole description of a key, not the part that 80 columns show", function()
  start()
  local size = api.ui_size
  api.ui_size = function() return 80, 24 end
  T.after(function()
    api.ui_size = size
    while paw.ui.float do
      paw.ui.close()
    end
  end)
  for _, lhs in ipairs({ "?", "<Space>fk" }) do
    paw.keymap.feed(lhs)
    local shown = paw.pick.state().matches
    local cut
    for _, line in ipairs(shown) do
      if line:match("^gm ") then cut = line end
    end
    eq(
      cut ~= nil and cut:find("metronome", 1, true) == nil,
      true,
      lhs .. ": the line of gm is cut before the word: " .. tostring(cut)
    )
    paw.keymap.feed("metronome")
    local found = false
    for _, line in ipairs(paw.pick.state().matches) do
      if line:match("^gm ") then found = true end
    end
    eq(found, true, lhs .. ": metronome finds gm")
    paw.keymap.feed("<Esc>")
  end
end)

test("the device panel's cursor starts on the first device of another part, so w goes to a device", function()
  start()
  local a = paw.add_part({ name = "A" })
  a:add_device("synth")
  a:add_device("delay")
  local b = paw.add_part({ name = "B" })
  b:add_device("synth")
  b:add_device("delay")
  paw.cursor.set_part(a)
  paw.ui.focus("devices")
  T.after(function()
    paw.ui.hide("devices")
    paw.ui.focus("arrange")
  end)
  local panel = paw.ui.views:get("devices")
  paw.keymap.feed("G")
  eq(panel.row > 1, true, "G goes down the chain of A")
  paw.cursor.set_part(b)
  local _, row = panel:selected()
  eq(panel.row, 1, "on B the cursor is on the first row")
  eq(row.param, nil, "a device's own row")
  paw.keymap.feed("w")
  _, row = panel:selected()
  eq(row.param == nil and row.device.kind, "delay", "w goes to the next device")
end)

test("the device panel's cursor starts on the first device in another project", function()
  start()
  local a = paw.add_part({ name = "A" })
  a:add_device("synth")
  a:add_device("delay")
  local path = paw.project.save(T.scratch .. "/panel-row")
  paw.cursor.set_part(a)
  paw.ui.focus("devices")
  T.after(function()
    paw.ui.hide("devices")
    paw.ui.focus("arrange")
  end)
  local panel = paw.ui.views:get("devices")
  paw.keymap.feed("G")
  eq(panel.row > 1, true, "G goes down the chain")
  paw.project.load(path)
  paw.flush()
  paw.cursor.set_part(paw.parts()[1])
  local _, row = panel:selected()
  eq(panel.row .. " " .. tostring(row.param), "1 nil", "the same part id in the project opened: the first row")
end)

test(
  "g' asks for the marker's name and never makes one without, and the list of markers finds names, not its line numbers",
  function()
    start()
    for i, name in ipairs({ "Intro", "Verse", "Chorus", "Bridge" }) do
      paw.markers.add((i - 1) * 16, name)
    end
    paw.markers.add(64, "Chorus 2")
    paw.cursor.set_beat(80)
    keys("g'")
    eq(#paw.markers.list(), 5, "a prompt asks first")
    keys("<CR>")
    local last = paw.markers.list()[#paw.markers.list()]
    eq(last.name, "Marker 6", "Enter alone keeps the name it offers")
    keys('g"')
    keys("Chorus 2")
    local lines = paw.pick.state().matches
    eq(lines[1]:find("Chorus 2", 1, true) ~= nil, true, "Chorus 2 first: " .. tostring(lines[1]))
    for _, line in ipairs(lines) do
      eq(line:find("Verse", 1, true), nil, "line 2 (Verse) does not match by its number: " .. line)
    end
    keys("<CR>")
    eq(paw.cursor.beat, 64, "and Enter goes there")
  end
)

test("the piano roll names the rows of a part with the drums device: kick, snare, closed hat", function()
  start()
  local t = paw.add_part({ name = "Drums" })
  t:add_device("drums")
  local c = t:add_clip({ start = 0, length = 4 })
  local roll = paw.ui.views:get("pianoroll")
  roll:edit(c)
  T.after(function()
    roll.clip_id = nil
    paw.ui.hide("pianoroll")
    paw.ui.focus("arrange")
  end)
  paw.ui.focus("pianoroll")
  roll:set(38, 0)
  local names = paw.plugins.key_names(t.id)
  eq(names[36] .. "/" .. names[38] .. "/" .. names[42], "Kick/Snare/Closed hat", "the kit's pieces by pitch")
  local screen = table.concat(api.ui_snapshot(120, 40), "\n")
  eq(
    screen:find("Snare", 1, true) ~= nil and screen:find("Kick", 1, true) ~= nil,
    true,
    "the rows show them:\n" .. screen
  )
end)

test("ext.unload takes away the key bar lines that the extension set", function()
  start()
  local dir = T.scratch .. "/barext"
  os.execute("mkdir -p '" .. dir .. "'")
  T.write_file(
    dir .. "/init.lua",
    [[
paw.keymap.set("Z1", function() end, { view = "barview", desc = "test" })
paw.ui.keybar.set("barview", "n", { { "Z1", "one" } })
]]
  )
  local entry = paw.ext.load(dir)
  eq(entry.ok, true, "loads")
  eq(paw.ui.keybar.lines.barview ~= nil, true, "its line is there")
  eq(paw.ext.unload("barext"), true, "unloads")
  eq(paw.ui.keybar.lines.barview, nil, "and its line is gone")
  eq(table.concat(paw.ui.keybar.check(), ", "), "", "no line shows a key that is not mapped")
end)

test("a count before Alt-j and Alt-k moves the part that many places, and before & makes that many copies", function()
  start()
  for _, name in ipairs({ "A", "B", "C", "D", "E" }) do
    paw.add_part({ name = name })
  end
  local function order()
    local out = {}
    for _, t in ipairs(paw.parts()) do
      out[#out + 1] = t.name
    end
    return table.concat(out)
  end
  paw.cursor.set_part(paw.parts()[1])
  keys("3<A-j>")
  eq(order(), "BCDAE", "3 Alt-j moves A down three places")
  eq(paw.cursor.part().name, "A", "the cursor goes with it")
  keys("9<A-j>")
  eq(order(), "BCDEA", "a count past the end stops at the last place")
  keys("2<A-k>")
  eq(order(), "BCADE", "2 Alt-k moves it up two")
  paw.undo()
  eq(order(), "BCDEA", "one undo step")
  local t = paw.parts()[1]
  t:add_clip({ start = 0, length = 4, name = "riff" })
  api.undo_checkpoint()
  paw.cursor.set_part(t)
  paw.cursor.set_beat(0)
  keys("3&")
  eq(T.layout(t), "riff@0+4 riff@4+4 riff@8+4 riff@12+4", "3& makes three copies, one after the other")
  eq(paw.cursor.beat, 12, "the cursor goes to the last")
  paw.undo()
  eq(#t:clips(), 1, "one undo step")
end)
