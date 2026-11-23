-- The fuzzy picker, `paw.pick`: the matcher, the view, and every source.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api
local pick = paw.pick

--- The texts `pick.filter` returns, best first.
local function ranked(query, list)
  local out = {}
  for i, r in ipairs(pick.filter(query, list)) do
    out[i] = r.text
  end
  return out
end

local function screen(w, h) return table.concat(api.ui_snapshot(w or 100, h or 30), "\n") end

local function has(text, part, what)
  if not text:find(part, 1, true) then error(string.format("%s: %q is not in\n%s", what or "text", part, text), 2) end
end

local function start()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  if paw.ui.float then paw.ui.close() end
  paw.ui.focus("arrange")
end

--- Open the picker named `name`, type `query`, press Enter.
local function choose(name, query)
  paw.pick(name)
  eq(pick.state() ~= nil, true, name .. " picker is open")
  paw.keymap.feed((query or "") .. "<CR>")
  eq(pick.state(), nil, name .. " picker closed after Enter")
end

-- Matching -------------------------------------------------------------------

test("pick: matching is a subsequence, in order", function()
  eq(pick.match("bss", "Bass Synth") ~= nil, true, "b-s-s is in Bass Synth")
  eq(pick.match("ssb", "Bass Synth"), nil, "out of order is no match")
  eq(pick.match("x", "Bass"), nil, "a missing character is no match")
  local score, positions = pick.match("bs", "Bass Synth")
  eq(score > 0, true, "a score")
  eq(table.concat(positions, ","), "1,6", "B and the S that starts a word")
  eq(select(2, pick.match("hall drag", "Dragonfly Hall")) ~= nil, true, "words of the query match apart")
  eq(pick.match("hall drum", "Dragonfly Hall"), nil, "and every one must match")
end)

test("pick: lower case ignores case, a capital does not", function()
  eq(#ranked("bass", { "BASS", "bass", "Bass" }), 3, "lower case matches any case")
  eq(table.concat(ranked("Ba", { "bass", "Bass", "BASS" }), " "), "Bass", "a capital matches as typed")
end)

test("pick: ranking prefers runs, word starts and short lines", function()
  eq(ranked("ver", { "xvaexr", "xaverx" })[1], "xaverx", "consecutive characters")
  eq(ranked("dh", { "dashboard", "Dragonfly Hall" })[1], "Dragonfly Hall", "word starts")
  eq(ranked("tp", { "setup", "transport.play" })[1], "transport.play", "after a separator")
  eq(ranked("ms", { "mono synth", "mysynth" })[1], "mono synth", "two word starts beat a run in one word")
  eq(
    table.concat(ranked("bass", { "a big bad ass sound", "Bass Synth", "Bass" }), "|"),
    "Bass|Bass Synth|a big bad ass sound",
    "shorter first, scattered last"
  )
  eq(ranked("cs", { "clipSplit", "chorus" })[1], "clipSplit", "a capital inside a word starts one")
  eq(table.concat(ranked("", { "c", "a", "b" }), ""), "cab", "an empty query keeps the order")
end)

-- The view -------------------------------------------------------------------

test("pick: the call as other extensions make it", function()
  start()
  local chosen, cancelled
  local bass = { text = "Bass", id = 3 }
  paw.pick({
    title = "Tracks",
    items = { bass, { text = "Drums", id = 4 }, "Lead" },
    on_choose = function(item) chosen = item end,
    on_cancel = function() cancelled = true end,
  })
  eq(paw.ui.float and paw.ui.float.name, "pick", "a floating view")
  eq(#pick.state().matches, 3, "everything before typing")
  paw.keymap.feed("bs")
  eq(table.concat(pick.state().matches, ","), "Bass", "typing narrows")
  paw.keymap.feed("<CR>")
  eq(chosen, bass, "Enter chooses the very item given")
  eq(paw.ui.float, nil, "and closes")
  eq(paw.ui.focused, "arrange", "focus goes back")

  chosen = nil
  paw.pick({
    items = { "one", "two" },
    on_choose = function(item) chosen = item end,
    on_cancel = function() cancelled = true end,
  })
  paw.keymap.feed("<C-n><CR>")
  eq(chosen, "two", "a plain string item comes back as the string")

  paw.pick({
    items = function() return { { name = "x" }, { name = "y" } } end,
    format = function(i) return "item " .. i.name end,
    on_choose = function(item) chosen = item end,
  })
  eq(pick.state().matches[2], "item y", "items from a function, lines from format")
  paw.keymap.feed("y<CR>")
  eq(chosen.name, "y", "matched on the formatted line")

  paw.pick({ items = { "a" }, on_choose = function() end, on_cancel = function() cancelled = true end })
  paw.keymap.feed("<Esc>")
  eq(cancelled, true, "Escape cancels")
  eq(paw.ui.float, nil, "and closes")
  paw.pick({ items = { "a" }, on_choose = function() end })
  paw.keymap.feed("<Esc>")
  eq(paw.ui.float, nil, "on_cancel is optional")
end)

test("pick: keys move, clear and edit the query", function()
  start()
  local chosen
  paw.pick({ items = { "alpha", "beta", "gamma", "delta" }, on_choose = function(item) chosen = item end })
  local function sel() return pick.state().item end
  paw.keymap.feed("<C-n>")
  eq(sel(), "beta", "C-n")
  paw.keymap.feed("<Down><C-j>")
  eq(sel(), "delta", "Down and C-j")
  paw.keymap.feed("<C-n>")
  eq(sel(), "alpha", "past the end wraps")
  paw.keymap.feed("<C-p>")
  eq(sel(), "delta", "C-p wraps back")
  paw.keymap.feed("<Up><C-k>")
  eq(sel(), "beta", "Up and C-k")
  paw.keymap.feed("ta")
  eq(table.concat(pick.state().matches, ","), "beta,delta", "typing narrows")
  eq(sel(), "beta", "and selects the best")
  paw.keymap.feed("<BS><BS>")
  eq(#pick.state().matches, 4, "Backspace widens again")
  paw.keymap.feed("ga<C-u>")
  eq(pick.state().query, "", "C-u clears")
  eq(#pick.state().matches, 4, "and everything is back")
  paw.keymap.feed("zzz")
  eq(#pick.state().matches, 0, "nothing matches")
  has(screen(), "Nothing matches.", "says so")
  paw.keymap.feed("<C-w>e<Space>t<CR>")
  eq(chosen, "beta", "C-w deletes a word; a space starts another")
end)

test("pick: the screen as text marks the selection with a character", function()
  start()
  paw.pick({ title = "Fruit", items = { "apple", "banana", "cherry" }, on_choose = function() end })
  paw.keymap.feed("an<C-n>")
  local text = screen(100, 30)
  has(text, "Fruit", "the title")
  has(text, "> an", "the query")
  has(text, "1/3", "how many match")
  has(text, "▶ banana", "the selected line")
  local float = paw.frontend.float(100, 30)
  eq(float.title, "Fruit", "the frontend gets the title")
  local found
  for _, line in ipairs(float.lines) do
    if line:find("▶ banana", 1, true) then found = true end
  end
  eq(found, true, "and the selected line as plain text")
  paw.keymap.feed("<Esc>")
end)

test("pick: preview, actions, multi-select and resume", function()
  start()
  local acted, many
  paw.pick({
    title = "Things",
    items = { "one", "two", "three" },
    on_choose = function() end,
    preview = function(item) return { "about " .. item } end,
    actions = { ["<C-e>"] = { fn = function(item, query) acted = item .. "|" .. query end, desc = "act" } },
  })
  paw.keymap.feed("tw")
  has(screen(110, 30), "about two", "the preview shows the selected item")
  has(screen(110, 30), "e act", "and the footer lists the extra key")
  paw.keymap.feed("<C-e>")
  eq(acted, "two|tw", "an action gets the item and the query")
  eq(paw.ui.float, nil, "and closes the picker")
  pick.resume()
  eq(pick.state().query, "tw", "resume brings back the query")
  paw.keymap.feed("<Esc>")

  paw.pick({
    items = { "a", "b", "c" },
    multi = true,
    on_choose = function() end,
    on_choose_multi = function(items) many = items end,
  })
  paw.keymap.feed("<Tab><C-n><Tab><CR>")
  eq(table.concat(many, ","), "a,c", "Tab marks several")
end)

-- Sources --------------------------------------------------------------------

test("pick: the letter after <leader>f is the domain's letter: fc clips, fr regions, fm markers, ft tracks", function()
  start()
  paw.add_track({ name = "Bass" })
  for keys, title in pairs({
    ["<Space>fc"] = "Clips",
    ["<Space>fr"] = "Regions",
    ["<Space>fm"] = "Markers",
    ["<Space>ft"] = "Tracks",
    ["<Space>f:"] = "Commands",
    ["<Space>da"] = "Add a device",
  }) do
    paw.keymap.feed(keys)
    eq(pick.state() and pick.state().title, title, keys)
    paw.keymap.feed("<Esc>")
  end
end)

test("pick: commands runs the one chosen", function()
  start()
  local ran = 0
  paw.command("zz_pick_test", function() ran = ran + 1 end, { desc = "for the picker test" })
  choose("commands", "zz_pick_test")
  eq(ran, 1, "ran it")
  paw.cmd("pick.commands", { "zz_pick_test" })
  eq(pick.state().query, "zz_pick_test", "a command with a query")
  paw.keymap.feed("<CR>")
  eq(ran, 2, "ran it again")
end)

test("pick: keys runs the mapping chosen", function()
  start()
  local ran
  paw.keymap.set("gQ", function() ran = true end, { view = "arrange", desc = "zz picker mapping" })
  choose("keys", "zz picker")
  eq(ran, true, "ran the mapping")
  paw.keymap.del("gQ", { view = "arrange" })
end)

test("pick: tracks and clips move the cursor", function()
  start()
  local bass = paw.add_track({ name = "Bass" })
  local drums = paw.add_track({ name = "Drums" })
  bass:add_clip({ name = "verse", start = 8, length = 4 })
  drums:add_clip({ name = "fill", start = 12, length = 4 })
  paw.cursor.set_track(bass)
  choose("tracks", "drum")
  eq(paw.cursor.track_id(), drums.id, "on the track")
  paw.cursor.set_beat(0)
  choose("clips", "verse")
  eq(paw.cursor.track_id(), bass.id, "on the clip's track")
  eq(paw.cursor.beat, 8, "at its start")
  paw.keymap.feed("<C-o>")
  eq(paw.cursor.track_id(), drums.id, "and C-o goes back")
end)

test("pick: devices adds to the track, and device.add asks with it", function()
  start()
  local track = paw.add_track({ name = "T" })
  paw.cursor.set_track(track)
  choose("devices", "delay")
  eq(track:devices()[1] and track:devices()[1].kind, "delay", "added the delay")
  paw.keymap.feed("a")
  eq(pick.state() and pick.state().title, "Add a device", "`a` opens the picker")
  paw.keymap.feed("synth<CR>")
  eq(track:devices()[2].kind, "synth", "and adds what is chosen")
  paw.cmd("device.add", { "gain" })
  eq(track:devices()[3].kind, "gain", "device.add with a name still adds at once")
  eq(pick.state(), nil, "without a picker")

  paw.ui.focus("arrange")
  choose("track_devices", "synth")
  eq(paw.ui.focused, "devices", "the device panel")
  eq(paw.ui.views.devices:selected().kind, "synth", "on the device chosen")
  paw.ui.focus("arrange")
end)

test("pick: marks, registers and messages", function()
  start()
  local a = paw.add_track({ name = "A" })
  local b = paw.add_track({ name = "B" })
  paw.cursor.set_track(b)
  paw.cursor.set_beat(5)
  paw.keymap.feed("mq")
  paw.cursor.set_track(a)
  paw.cursor.set_beat(0)
  choose("marks", "q")
  eq(paw.cursor.track_id(), b.id, "the mark's track")
  eq(paw.cursor.beat, 5, "the mark's beat")

  paw.cursor.set_track(a)
  paw.keymap.setreg({ kind = "keys", keys = "j" }, "m")
  choose("registers", "macro")
  eq(paw.cursor.track_id(), b.id, "a macro plays")
  paw.cursor.set_track(a)
  paw.keymap.feed("yy")
  choose("registers", '"0')
  eq(#api.track_list(), 3, "a register of tracks is pasted")

  paw.notify("zz picker message\nwith a second line")
  paw.pick("messages")
  eq(pick.state().matches[1]:find("zz picker message", 1, true) ~= nil, true, "the newest message first")
  has(screen(110, 30), "with a second line", "the preview shows all of it")
  paw.keymap.feed("<CR>")
  eq(paw.ui.float and paw.ui.float.title, "Message", "Enter shows it in a page")
  paw.ui.close()
end)

test("pick: files opens projects and imports audio", function()
  start()
  local dir = T.scratch .. "/pickfiles"
  os.execute("mkdir -p '" .. dir .. "/sub/.hidden'")
  local t = paw.add_track({ name = "Saved" })
  paw.project.save(dir .. "/song.json")
  T.write_file(dir .. "/notes.json", '{"not": "a project"}')
  os.execute("cp tests/fixtures/tone-mono-8k.wav '" .. dir .. "/sub/take.wav'")
  os.execute("cp tests/fixtures/tone-mono-8k.wav '" .. dir .. "/sub/.hidden/no.wav'")
  local found = {}
  for _, f in ipairs(pick.walk(dir, 1000)) do
    found[#found + 1] = f.kind .. ":" .. f.path:sub(#dir + 2)
  end
  table.sort(found)
  eq(
    table.concat(found, " "),
    "audio:sub/take.wav project:song.json",
    "projects and audio, not other JSON or hidden files"
  )

  -- The real source walks the working directory, the repository here.
  paw.project.new()
  t = paw.add_track({ name = "Import" })
  paw.pick("files")
  while pick.state().note do
    paw.wait(5)
  end
  paw.cursor.set_track(t)
  paw.cursor.set_beat(4)
  paw.keymap.feed("fixtures tone-mono-8k.wav<CR>")
  local clips = api.clip_list(t.id)
  eq(#clips, 1, "imported at the cursor")
  eq(clips[1].start, 4, "where the cursor is")
  eq(clips[1].kind, "audio", "as audio")

  paw.project.save(dir .. "/import.json")
  paw.pick.sources.files.on_choose({ path = dir .. "/song.json", kind = "project" })
  eq(paw.tracks()[1].name, "Saved", "a project opens")
end)

test("pick: files reads in slices, skips build folders and says when it stops", function()
  start()
  local dir = T.scratch .. "/pickwalk"
  os.execute("mkdir -p '" .. dir .. "/target' '" .. dir .. "/ignored' '" .. dir .. "/a/b/c'")
  for _, f in ipairs({ "target/no.wav", "ignored/no.wav", "a/yes.wav", "a/b/c/deep.wav" }) do
    os.execute("cp tests/fixtures/tone-mono-8k.wav '" .. dir .. "/" .. f .. "'")
  end
  T.write_file(dir .. "/.gitignore", "ignored/\n")
  local function names(list)
    local out = {}
    for i, f in ipairs(list) do
      out[i] = f.path:sub(#dir + 2)
    end
    table.sort(out)
    return table.concat(out, " ")
  end
  eq(names(pick.walk(dir, 1000)), "a/b/c/deep.wav a/yes.wav", "build and ignored folders are left out")
  eq(names(pick.walk(dir, 1000, 1)), "a/yes.wav", "a depth stops the walk")

  -- The picker opens at once and fills as the walk goes on; at the limit it says so.
  paw.opt.files_limit = 100
  paw.keymap.feed(" ff")
  eq(pick.state() ~= nil, true, "the picker is open before the walk is done")
  local waited = 0
  while pick.state().note and not pick.state().note:find("stopped") and waited < 2000 do
    paw.wait(5)
    waited = waited + 5
  end
  eq(pick.state().note, "stopped at 100 entries (files_limit)", "the picker says it stopped at the limit")
  has(screen(), "stopped at 100 entries", "the query line shows it")
  paw.keymap.feed("<Esc>")
  eq(pick.state(), nil, "Esc closes it")
  paw.opt.files_limit = 20000
end)

test("pick: options switch or ask for a value", function()
  start()
  local hints = paw.opt.hints
  choose("options", "hints")
  eq(paw.opt.hints, not hints, "a boolean switches")
  paw.opt.hints = hints
  paw.pick("options", { query = "clip_length" })
  paw.keymap.feed("<CR><C-u>8<CR>")
  eq(paw.opt.clip_length, 8, "a number is asked for")
  paw.opt.clip_length = 4
  paw.keymap.feed("<Esc>")
end)

test("pick: sources can be added, and the picker of pickers lists them", function()
  start()
  local got
  paw.pick.sources.zz_test = { desc = "a test source", items = { "x", "y" }, on_choose = function(item) got = item end }
  paw.cmd("pick")
  eq(pick.state().title, "Pickers", ":pick with no name")
  paw.keymap.feed("zz_test<CR>")
  eq(pick.state() and pick.state().title, "zz_test", "opens the chosen source")
  paw.keymap.feed("y<CR>")
  eq(got, "y", "which works")
  paw.pick.sources.zz_fn = function()
    return { title = "Made", items = { "z" }, on_choose = function(item) got = item end }
  end
  paw.commands.exec("pick zz_fn")
  eq(pick.state().title, "Made", "a source can be a function")
  paw.keymap.feed("<CR>")
  eq(got, "z", "chosen")
  paw.pick.sources.zz_test, paw.pick.sources.zz_fn = nil, nil
end)
