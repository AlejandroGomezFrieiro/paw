-- Tests for the undo tree extension, run by tests/suite.lua.
local T = ...
local paw = require("paw")
local api = paw.api
local test, eq, near = T.test, T.eq, T.near

local function ext()
  if not paw.ext.loaded.undotree then paw.ext.load("extensions/undotree") end
  return require("undotree")
end

--- A fresh project with one part, and the extension loaded.
local function start()
  local u = ext()
  T.fresh()
  paw.keymap.feed("<Esc><Esc>")
  paw.ui.close()
  paw.ui.focus("arrange")
  u.clear_ab()
  return u
end

local function names(part)
  local out = {}
  for _, c in ipairs(part:clips()) do
    out[#out + 1] = c.name
  end
  return table.concat(out, " ")
end

local function step(fn)
  fn()
  api.undo_checkpoint()
  return api.undo_current()
end

test("undotree: undo then edit keeps the old branch reachable", function()
  start()
  local t
  local root = api.undo_current()
  local s1 = step(function() t = paw.add_part({ name = "T" }) end)
  local s2 = step(function() t:add_clip({ name = "old", start = 0, length = 4 }) end)
  eq(paw.undo(), true, "undo")
  eq(names(t), "", "the clip is gone")
  local s3 = step(function() t:add_clip({ name = "new", start = 4, length = 4 }) end)
  eq(names(t), "new", "the new branch")
  eq(paw.redo(), false, "nothing to redo at the end of a branch")
  local tree = ext().tree()
  eq(#tree.states, 4, "four states")
  eq(tree.by_id[s2].parent, s1, "the old branch hangs from #" .. s1)
  eq(tree.by_id[s3].parent, s1, "and so does the new one")
  eq(tree.by_id[s1].parent, root, "from the root")
  eq(api.undo_goto(s2), true, "go to the old branch")
  eq(names(t), "old", "the old clip is back")
  eq(paw.undo(), true, "undo")
  eq(paw.redo(), true, "redo follows the branch last visited")
  eq(names(t), "old", "back on the old branch")
  eq(api.undo_goto(s3), true, "and to the new one")
  eq(names(t), "new", "the new clip")
  eq(api.undo_goto(999999), false, "no such state")
  -- A state knows when it was made and what made it.
  paw.cmd("part.add", { "Cmd" })
  api.undo_checkpoint()
  local last = ext().tree().by_id[api.undo_current()]
  eq(last.label, "Add a part below the cursor", "the command's description is the label")
  near(last.time, os.time(), 5, "made now")
  paw.ui.focus("arrange")
  paw._kernel.key("O")
  api.undo_checkpoint()
  last = ext().tree().by_id[api.undo_current()]
  eq(last.keys, "O", "the keys typed are kept")
end)

test("undotree: g- and g+ visit every state in time order", function()
  local u = start()
  local ids = { api.undo_current() }
  local t
  ids[#ids + 1] = step(function() t = paw.add_part({ name = "T" }) end)
  ids[#ids + 1] = step(function() t.volume = -1 end)
  paw.undo()
  ids[#ids + 1] = step(function() t.volume = -2 end)
  paw.undo()
  paw.undo()
  ids[#ids + 1] = step(function() paw.add_part({ name = "U" }) end)
  local seen = { api.undo_current() }
  for _ = 1, #ids do
    T.keys("g-")
    if api.undo_current() ~= seen[#seen] then seen[#seen + 1] = api.undo_current() end
  end
  eq(
    table.concat(seen, " "),
    table.concat({ ids[5], ids[4], ids[3], ids[2], ids[1] }, " "),
    "g- goes back through every state"
  )
  seen = { api.undo_current() }
  for _ = 1, #ids do
    T.keys("g+")
    if api.undo_current() ~= seen[#seen] then seen[#seen + 1] = api.undo_current() end
  end
  eq(table.concat(seen, " "), table.concat(ids, " "), "g+ forward through every state")
  T.keys("3g-")
  eq(api.undo_current(), ids[2], "a count")
  eq(paw.parts()[1].volume, 0, "and the project is that state")
  -- :earlier and :later, by count and by time.
  paw.cmd("later", { 2 })
  eq(api.undo_current(), ids[4], ":later 2")
  eq(paw.parts()[1].volume, -2, "the branch with -2 dB")
  paw.cmd("earlier", { "1h" })
  eq(api.undo_current(), ids[1], ":earlier 1h goes back to the start")
  eq(#paw.parts(), 0, "an empty project")
  paw.cmd("later", { "10m" })
  eq(api.undo_current(), ids[5], ":later 10m to the newest")
  eq(u.parse_amount("2m").seconds, 120, "minutes")
  eq(u.parse_amount("30s").seconds, 30, "seconds")
  eq(u.parse_amount("5").steps, 5, "a count")
  eq(u.parse_amount("5x"), nil, "nonsense")
end)

test("undotree: what differs between two states", function()
  start()
  local t, clip
  local s0 = api.undo_current()
  local s1 = step(function()
    t = paw.add_part({ name = "Bass" })
    t:add_device("synth", { cutoff = 900 })
    clip = t:add_clip({
      name = "riff",
      start = 0,
      length = 4,
      notes = { { pitch = 40, start = 0 }, { pitch = 43, start = 1 }, { pitch = 45, start = 2 } },
    })
  end)
  local s2 = step(function()
    t.volume = -6
    t:devices()[1]:set("cutoff", 500)
    local notes = clip:notes()
    notes[2].velocity = 30
    table.remove(notes, 3)
    notes[#notes + 1] = { pitch = 47, start = 3 }
    notes[#notes + 1] = { pitch = 48, start = 3.5 }
    clip:set_notes(notes)
    paw.add_part({ name = "Keys" })
  end)
  local d = api.undo_diff(s0, s1)
  eq(d.parts.added, 1, "a part added")
  eq(d.devices.added, 1, "a device added")
  eq(d.clips.added, 1, "a clip added")
  d = api.undo_diff()
  eq(d.from, s1, "the last step: from its parent")
  eq(d.to, s2, "to the current state")
  eq(d.parts.added, 1, "Keys added")
  eq(d.parts.changed, 1, "Bass changed")
  eq(d.devices.changed, 1, "the synth changed")
  eq(d.clips.changed, 1, "the clip changed")
  eq(d.notes.added, 2, "two notes added")
  eq(d.notes.removed, 1, "one removed")
  eq(d.notes.changed, 1, "one changed")
  local text = table.concat(d.items, "\n")
  eq(text:find("~ device synth on part Bass: cutoff", 1, true) ~= nil, true, "readable lines: " .. text)
  eq(ext().summary(d):find("2 notes added", 1, true) ~= nil, true, "a summary")
  d = api.undo_diff(s2, s0)
  eq(d.parts.removed, 2, "backwards: both parts removed")
  eq(api.undo_diff(s1, s1).same, true, "a state against itself")
end)

test("undotree: named states survive saving and reopening", function()
  local u = start()
  local path = T.scratch .. "/checkpoints-song.json"
  local t = paw.add_part({ name = "T" })
  api.undo_checkpoint()
  eq(api.checkpoint_dir(), nil, "an unsaved project has no checkpoint folder")
  -- Before the project has a file the name is kept, and written on saving.
  local first = u.checkpoint("intro")
  eq(first.pending, true, "waiting for a file")
  t:add_clip({ name = "verse", start = 0, length = 4 })
  api.undo_checkpoint()
  eq(paw.project.modified, true, "modified")
  paw.project.save(path)
  paw.flush()
  eq(paw.project.modified, false, "not modified once saved")
  local dir = api.checkpoint_dir()
  eq(dir, T.scratch .. "/checkpoints-song.checkpoints", "the folder beside the project")
  eq(#api.checkpoint_list(), 1, "the waiting one was written")
  eq(api.checkpoint_list()[1].name, "intro", "under its name")
  paw.cmd("checkpoint", { "before the bridge" })
  t:add_clip({ name = "bridge", start = 4, length = 4 })
  api.undo_checkpoint()
  eq(paw.project.modified, true, "modified after an edit")
  paw.undo()
  eq(paw.project.modified, false, "and not after undoing back to what was saved")
  paw.redo()
  paw.project.save(path)

  paw.project.load(path)
  paw.flush()
  eq(names(paw.parts()[1]), "verse bridge", "reopened as saved")
  local list = api.checkpoint_list()
  eq(#list, 2, "both checkpoints listed after reopening")
  eq(list[2].name, "before the bridge", "names with spaces")
  local items = u.items()
  eq(items[1].name, "before the bridge", "newest first")
  paw.cmd("checkpoint.restore", { "intro" })
  eq(names(paw.parts()[1]), "", "the intro state is back")
  local tree = u.tree()
  eq(tree.by_id[tree.current].name, "intro", "as a named state")
  eq(paw.undo(), true, "which undo leaves")
  eq(names(paw.parts()[1]), "verse bridge", "back to what was opened")
  paw.cmd("checkpoint.restore", { "1" })
  eq(names(paw.parts()[1]), "verse", "by number")
  -- Without a picker the list is a page.
  local pick = paw.pick
  paw.pick = nil
  paw.cmd("checkpoints")
  local text = table.concat(api.ui_snapshot(100, 30), "\n")
  eq(text:find("before the bridge", 1, true) ~= nil, true, "the page lists them")
  paw.ui.close()
  -- With one, it gets the items.
  local got
  paw.pick = function(opts) got = opts end
  paw.cmd("checkpoints")
  eq(got.title, "Checkpoints", "the picker is used")
  eq(#got.items, 2, "with every checkpoint")
  got.on_choose(got.items[2])
  eq(names(paw.parts()[1]), "", "choosing restores")
  paw.pick = pick
  api.checkpoint_delete(list[1].file)
  eq(#api.checkpoint_list(), 1, "deleted")
  T.fresh()
end)

test("undotree: A/B while playing keeps the transport going", function()
  local u = start()
  paw.project.tempo = 120
  local t = T.tone("AB", 64)
  t.volume = -3
  api.undo_checkpoint()
  local a = u.mark_a()
  t.volume = -12
  t:clips()[1].name = "changed"
  api.undo_checkpoint()
  local b = api.undo_current()
  eq(u.toggle(), "A", "to A")
  eq(t.volume, -3, "A's mix")
  eq(u.toggle(), "B", "and back")
  eq(t.volume, -12, "B's mix")
  paw.transport.seek(0)
  paw.transport.play()
  T.until_beat(1)
  for i = 1, 4 do
    -- The stepped engine plays only when the clock moves: the switch itself
    -- must leave the playhead where it was, to the sample.
    paw.flush()
    local before = paw.transport.position
    paw.cmd("ab.toggle")
    paw.flush()
    eq(paw.transport.playing, true, "still playing after switch " .. i)
    eq(paw.transport.position, before, "no jump of the playhead at switch " .. i)
    eq(api.undo_current(), i % 2 == 1 and a or b, "switch " .. i .. " went to " .. (i % 2 == 1 and "A" or "B"))
    eq(t.volume, i % 2 == 1 and -3 or -12, "and the engine has that mix")
    -- The position keeps moving after the switch.
    T.until_beat(before + 0.2)
  end
  -- The part is sounding: its synth runs blocks, and does not sleep.
  T.next_block(2, t:devices()[1].id)
  paw.transport.stop()
  -- The key does the same.
  paw.ui.focus("arrange")
  T.keys("<leader>pb")
  eq(api.undo_current(), a, "the A/B key")
  u.clear_ab()
end)

test("undotree: the view draws the tree and goes to a state", function()
  local u = start()
  local t
  local s1 = step(function() t = paw.add_part({ name = "T" }) end)
  local s2 = step(function() t:add_clip({ name = "one", start = 0, length = 4 }) end)
  paw.undo()
  local s3 = step(function() t:add_clip({ name = "two", start = 4, length = 4 }) end)
  api.undo_name("chorus")
  paw.cmd("undotree")
  local text = table.concat(api.ui_snapshot(120, 40), "\n")
  eq(text:find("Undo tree", 1, true) ~= nil, true, "the window: " .. text)
  eq(text:find("#" .. s3, 1, true) ~= nil, true, "the newest state")
  eq(text:find('"chorus"', 1, true) ~= nil, true, "its name")
  eq(text:find("@", 1, true) ~= nil, true, "the current state")
  eq(text:find("┘", 1, true) ~= nil, true, "a branch joining")
  eq(text:find("+ clip two on part T", 1, true) ~= nil, true, "what the state changed")
  -- The rows: two branches from s1.
  local rows = u.rows(u.tree())
  eq(rows[1].id, s3, "newest first")
  eq(rows[1].graph, "@", "the current state")
  eq(rows[2].id, s2, "then the old branch")
  eq(rows[2].graph, "│ *", "beside it")
  eq(rows[3].id, s1, "then where they split")
  eq(rows[3].graph, "*─┘", "joined")
  -- j moves down to the old branch, Enter goes there.
  paw.keymap.feed("j<CR>")
  eq(api.undo_current(), s2, "Enter went to the selected state")
  eq(names(t), "one", "the project is that state")
  text = table.concat(api.ui_snapshot(120, 40), "\n")
  eq(text:find("@", 1, true) ~= nil, true, "still open")
  paw.keymap.feed("q")
  eq(paw.ui.float, nil, "q closes it")
end)

test("undotree: in a window of its own it takes keys and clicks as in the terminal", function()
  start()
  local t
  step(function() t = paw.add_part({ name = "T" }) end)
  local s2 = step(function() t:add_clip({ name = "one", start = 0, length = 4 }) end)
  local s3 = step(function() t:add_clip({ name = "two", start = 4, length = 4 }) end)
  paw.cmd("undotree")
  paw.cmd("view.window")
  eq(paw.ui.float, nil, "the floating tree moves into a window")
  eq(paw.canvas.open_views.undotree.title, "Undo tree", "with its title")
  local cell = { w = 10, h = 20 }
  local function shown()
    local painted = paw.canvas.paint("undotree", 1200, 400, { cell = cell, fresh = true })
    local text = {}
    for _, op in ipairs(painted.ops) do
      if op[1] == "m" then text[#text + 1] = op[6] end
    end
    return table.concat(text, " ")
  end
  local snap = api.ui_view_snapshot("undotree", 120, 19)
  local first = {}
  for _, run in ipairs(snap.rows[1]) do
    first[#first + 1] = run.text
  end
  eq(table.concat(first):find("#" .. s3, 1, true) ~= nil, true, "the newest state first")
  eq(shown():find("#" .. s3, 1, true) ~= nil, true, "and in the window")
  paw.canvas.key("undotree", "j")
  paw.canvas.key("undotree", "<CR>")
  eq(api.undo_current(), s2, "j and Enter go to the state below")
  for _, key in ipairs({ "n", "<C-u>", "v", "e", "r", "s", "e", "<CR>" }) do
    paw.canvas.key("undotree", key)
  end
  eq(ext().tree().by_id[s2].name, "verse", "n names it, typed in the window")
  eq(shown():find('"verse"', 1, true) ~= nil, true, "which the window shows")
  -- A click on the first row chooses the newest state.
  paw.canvas.pointer("undotree", { kind = "down", x = 15, y = 5, button = "left" })
  paw.canvas.key("undotree", "<CR>")
  eq(api.undo_current(), s3, "a click and Enter go there")
  paw.canvas.key("undotree", "q")
  eq(paw.canvas.open_views.undotree, nil, "q closes the window")
  eq(paw.ui.focused, "arrange", "and the keyboard goes back")
end)

--- What a painted window of the tree drew: its nodes (the round rectangles,
--- by state, newest first), its texts and its paths.
local function painted_tree()
  local drawing = paw.canvas.paint("undotree_paint", 900, 500, { fresh = true })
  local nodes, texts, paths = {}, {}, {}
  for _, op in ipairs(drawing.ops) do
    if op[1] == "r" and op[9] > 0 and op[4] == op[5] and op[9] * 2 == op[4] then nodes[#nodes + 1] = op end
    if op[1] == "t" then texts[#texts + 1] = op[4] end
    if op[1] == "p" then paths[#paths + 1] = op end
  end
  table.sort(nodes, function(a, b) return a[3] < b[3] end)
  return nodes, table.concat(texts, "\n"), paths
end

test("undotree: the painted window draws the tree, goes where a node is clicked and says what a step was", function()
  start()
  local t
  local s1 = step(function() t = paw.add_part({ name = "T" }) end)
  local s2 = step(function() t:add_clip({ name = "old", start = 0, length = 4 }) end)
  paw.undo()
  local s3 = step(function() t:add_clip({ name = "new", start = 4, length = 4 }) end)
  local offered = {}
  for _, entry in ipairs(paw.canvas.openable()) do
    offered[entry.name] = entry.title
  end
  eq(offered.undotree_paint, "Undo tree", "the window offers the painted tree")
  eq(offered.undotree, nil, "instead of the terminal's")
  paw.canvas.open("undotree_paint")
  local nodes, text, paths = painted_tree()
  eq(#nodes, 4, "a node for each state")
  local current = 0
  for _, node in ipairs(nodes) do
    if node[7] == paw.canvas.palette.text then current = current + 1 end
  end
  eq(current, 1, "one is ringed as the current state")
  eq(nodes[1][6], paw.canvas.palette.select, "and the current state, the newest, is the highlight colour")
  local elbow = false
  for _, p in ipairs(paths) do
    if select(2, p[2]:gsub("L", "")) == 2 then elbow = true end
  end
  eq(elbow, true, "the old branch bends away from the new one")
  eq(text:find("#" .. s3, 1, true) ~= nil and text:find("#" .. s2, 1, true) ~= nil, true, "each state is labelled")
  -- A click on a node goes there.
  local node = nodes[2]
  paw.canvas.pointer(
    "undotree_paint",
    { kind = "down", x = node[2] + node[4] / 2, y = node[3] + node[5] / 2, button = "left" }
  )
  eq(api.undo_current(), s2, "a click on the second node goes to #" .. s2 .. " (the old branch)")
  local now = painted_tree()
  eq(now[2][6], paw.canvas.palette.select, "which is now the lit one")
  -- Resting on a node says what the step was.
  paw.canvas.pointer("undotree_paint", { kind = "hover", x = node[2], y = node[3] })
  local _, tip = painted_tree()
  eq(tip:find("after #" .. s1, 1, true) ~= nil, true, "the tip names the state it grew from")
  eq(tip:find("ago", 1, true) ~= nil, true, "and says when")
  -- The terminal's keys work in it, and q closes it.
  paw.canvas.key("undotree_paint", "k")
  paw.canvas.key("undotree_paint", "<CR>")
  eq(api.undo_current(), s3, "k and Enter go to the node above")
  paw.canvas.key("undotree_paint", "q")
  eq(paw.canvas.open_views.undotree_paint, nil, "q closes the window")
end)
