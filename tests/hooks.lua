-- Hooks: edits before and after they become undo steps, undo and redo,
-- saving, keys before the keymap, the selection and the views on screen,
-- and the table of every event in docs/reference/events.md. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local test, eq, fails = T.test, T.eq, T.fails
local api = paw.api

-- Listen for `name` for the rest of the test; returns what was heard.
local function hear(name, fn)
  local heard = {}
  local id = paw.on(name, function(e, n)
    heard[#heard + 1] = e
    if fn then return fn(e, n) end
  end)
  T.after(function() paw.off(id) end)
  return heard
end

-- The end of a turn, as between two key presses.
local function turn() paw.wait(0) end

local function names(changes)
  local out = {}
  for _, c in ipairs(changes) do
    out[#out + 1] = c.name
  end
  table.sort(out)
  return table.concat(out, " ")
end

test("edit.before and edit.after hear what a turn changed, once, as one undo step", function()
  T.fresh()
  turn()
  local before = hear("edit.before")
  local after = hear("edit.after")
  local t = paw.add_track({ name = "Heard" })
  t.volume = -6
  turn()
  eq(#before, 1, "edit.before once")
  eq(
    names(before[1].changes):find("track.added", 1, true) ~= nil,
    true,
    "with what changed: " .. names(before[1].changes)
  )
  eq(#after, 1, "edit.after once")
  eq(after[1].state, api.undo_current(), "with the undo state the edit made")
  turn()
  eq(#before, 1, "a turn that changes nothing is no edit")
  paw.undo()
  turn()
  eq(#before, 1, "nor is undoing")
  eq(paw.track("Heard"), nil, "the edit was one step")
end)

test("edit.before refuses an edit, and the project is as the turn found it", function()
  T.fresh()
  local keep = paw.add_track({ name = "Keep" })
  turn()
  local state = api.undo_current()
  hear("edit.before", function(e)
    for _, c in ipairs(e.changes) do
      if c.name == "track.removed" then return false, "tracks stay" end
    end
  end)
  local after = hear("edit.after")
  keep:remove()
  turn()
  eq(paw.track("Keep") ~= nil, true, "the track is back")
  eq(api.undo_current(), state, "and no undo step was made")
  eq(#after, 0, "edit.after did not hear of it")
  eq(paw.ui.messages[#paw.ui.messages].text, "not done: tracks stay", "the reason is shown")
  paw.track("Keep").name = "Renamed"
  turn()
  eq(paw.track("Renamed") ~= nil, true, "other edits go on")
end)

test("an edit.before handler's own edits join the step", function()
  T.fresh()
  turn()
  hear("edit.before", function(e)
    for _, c in ipairs(e.changes) do
      if c.name == "track.added" then
        local t = paw.track(c.payload.id)
        if t and t.name == "raw" then t.name = "cooked" end
      end
    end
  end)
  paw.add_track({ name = "raw" })
  turn()
  eq(paw.track("cooked") ~= nil, true, "the handler's answer")
  paw.undo()
  eq(#paw.tracks(), 0, "one undo takes both away")
end)

test("undo and redo are heard of, with the states and the step's label", function()
  T.fresh()
  turn()
  local undos, redos = hear("undo"), hear("redo")
  api.undo_label("my step")
  paw.add_track({ name = "U" })
  turn()
  local made = api.undo_current()
  paw.undo()
  eq(#undos, 1, "undo heard")
  eq(undos[1].from, made, "from the step")
  eq(undos[1].to, api.undo_current(), "to its parent")
  eq(undos[1].label, "my step", "with its label")
  paw.redo()
  eq(#redos, 1, "redo heard")
  eq(redos[1].to, made, "back to the step")
  api.undo_goto(undos[1].to)
  eq(#undos, 2, "going back in the tree is an undo")
  eq(undos[2].how, "goto", "and says how")
  paw.undo()
  paw.undo()
  eq(#undos, 2, "nothing to undo is not heard of")
end)

test("project.saving may refuse a save, and project.saved comes after one", function()
  T.fresh()
  local path = T.scratch .. "/hooks-save.json"
  local refuse = true
  local saving = hear("project.saving", function()
    if refuse then return false, "not yet" end
  end)
  local saved = hear("project.saved")
  fails(function() paw.project.save(path) end, "not saved: not yet", "a refused save")
  eq(io.open(path) == nil, true, "nothing written")
  refuse = false
  paw.project.save(path)
  paw.flush()
  eq(saving[#saving].path, path, "project.saving names the file")
  eq(#saved, 1, "project.saved after")
end)

test("key.pre sees each key first and may take it from the keymap", function()
  T.fresh()
  paw.add_track({ name = "A" })
  paw.add_track({ name = "B" })
  paw.flush()
  paw.cursor.set_track(paw.track("A"))
  local seen = hear("key.pre", function(e)
    if e.key == "j" then return false end
  end)
  paw._kernel.key("j")
  eq(paw.cursor.index(), 1, "a key taken does nothing")
  eq(seen[1].key, "j", "the key")
  eq(seen[1].view, "arrange", "the view")
  eq(seen[1].mode, "n", "the mode")
end)

test("selection.changed hears visual mode, its moves and its end", function()
  T.fresh()
  paw.keymap.feed("<Esc><Esc>")
  paw.add_track({ name = "A" })
  paw.add_track({ name = "B" })
  paw.flush()
  paw.cursor.set_track(paw.track("A"))
  turn()
  local heard = hear("selection.changed")
  -- The piano roll's clip gone from under it is no selection, and no error.
  local gone = paw.track("A"):add_clip({ start = 0, length = 4 })
  paw.roll_clips.open({ gone.id }, gone.id)
  gone:remove()
  paw.ui.focus("arrange")
  local errors = #paw.ui.messages
  turn()
  for i = errors + 1, #paw.ui.messages do
    eq(paw.ui.messages[i].level ~= "error", true, "no error: " .. paw.ui.messages[i].text)
  end
  local start = #heard
  paw.keymap.feed("v")
  turn()
  eq(#heard, start + 1, "opening a selection")
  eq(heard[#heard].kind, "region", "a region")
  eq(heard[#heard].view, "arrange", "of the arrange view")
  paw.keymap.feed("j")
  turn()
  eq(#heard, start + 2, "stretching it")
  eq(heard[#heard].region.r1 - heard[#heard].region.r0, 1, "over two rows")
  turn()
  eq(#heard, start + 2, "a turn that changes nothing says nothing")
  paw.keymap.feed("<Esc>")
  turn()
  eq(#heard, start + 3, "closing it")
  eq(heard[#heard].kind, nil, "nothing selected")
end)

test("view.opened and view.closed hear views come on and off the screen", function()
  T.fresh()
  turn()
  local opened, closed = hear("view.opened"), hear("view.closed")
  turn()
  paw.ui.toggle("mixer")
  turn()
  local found = false
  for _, e in ipairs(opened) do
    found = found or e.name == "mixer"
  end
  eq(found, true, "the mixer opened")
  paw.ui.toggle("mixer")
  turn()
  found = false
  for _, e in ipairs(closed) do
    found = found or e.name == "mixer"
  end
  eq(found, true, "and closed")
end)

test("ext.loaded and ext.unloaded are heard", function()
  local loaded, unloaded = hear("ext.loaded"), hear("ext.unloaded")
  local dir = T.scratch .. "/hooks-ext"
  os.execute("mkdir -p '" .. dir .. "'")
  T.write_file(dir .. "/heard.lua", "paw.command('heard.hi', function() end)")
  paw.ext.load(dir .. "/heard.lua")
  eq(loaded[#loaded].name, "heard", "loaded")
  eq(loaded[#loaded].ok, true, "and how it went")
  paw.ext.unload("heard")
  eq(unloaded[#unloaded].name, "heard", "unloaded")
end)

test("every event the runtime and the kernel emit is in the table of events", function()
  local doc = T.read_file("docs/reference/events.md")
  local section = doc:match("\n## Every event\n(.*)$")
  assert(section, "docs/reference/events.md has a section of every event")
  local listed = {}
  for name in section:gmatch("`([%w_.*]+)`") do
    listed[name] = true
  end
  local missing = {}
  local function check(name)
    if not listed[name] and not listed[name:match("^[^.]+") .. ".*"] then missing[name] = true end
  end
  local function scan(dir, ext, patterns)
    local p = io.popen("find " .. dir .. " -name '*." .. ext .. "'")
    for path in p:lines() do
      local text = T.read_file(path)
      for _, pattern in ipairs(patterns) do
        for name in text:gmatch(pattern) do
          check(name)
        end
      end
    end
    p:close()
  end
  scan(
    "runtime/lua/paw",
    "lua",
    { 'paw%.emit%("([%w_]+%.[%w_.]+)"', 'events%.emit%("([%w_]+%.[%w_.]+)"', 'paw%.emit, "([%w_]+%.[%w_.]+)"' }
  )
  scan("crates/paw-core/src", "rs", {
    'emit%(%s*"([%w_]+%.[%w_.]+)"',
    'push%(%(%s*"([%w_]+%.[%w_.]+)"',
    '%(%s*"([%w_]+%.[%w_.]+)",%s*json!',
    '%(%s*"([%w_]+%.[%w_.]+)",%s*with_',
  })
  -- The kinds of thing whose events are made by name: `clip.added`, `lane.removed`.
  for _, kind in ipairs({ "clip", "lane" }) do
    for _, what in ipairs({ "added", "changed", "removed" }) do
      check(kind .. "." .. what)
    end
  end
  local list = {}
  for name in pairs(missing) do
    list[#list + 1] = name
  end
  table.sort(list)
  eq(table.concat(list, " "), "", "events missing from the table")
end)
