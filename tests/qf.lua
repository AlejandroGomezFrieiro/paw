-- Tests of the quickfix list (paw.qf): lists from Lua and from the
-- diagnostics, going through them, its window, the history, location lists,
-- `:cdo` and `:cfix`, and what the program feeds it (renders, missing sound
-- files, plugins). Loaded by tests/suite.lua with its helpers.
local T = ...
local advance = T.advance
local eq, fresh = T.eq, T.fresh
local api = paw.api
local A = paw.address
local L = paw.layout
local qf = paw.qf

local W, H = 140, 40
local initial = L.capture()

-- Each test leaves no lists, no diagnostics, and the windows as they were.
local function test(name, fn)
  T.test(name, function()
    local result = { xpcall(fn, debug.traceback) }
    paw.diagnostic.reset()
    local s = qf.stack()
    s.lists, s.at = {}, 0
    for _, source in ipairs({ "render", "plugin scan", "tests" }) do
      qf.feed(source, {})
    end
    paw.keymap.feed("<Esc><Esc>")
    while paw.ui.float do
      paw.ui.close()
    end
    for view in pairs(paw.canvas.open_views) do
      paw.canvas.close(view)
    end
    L.restore(initial)
    paw.ui.views:get("pianoroll").clip_id = nil
    paw.ui.focus("arrange")
    if not result[1] then error(result[2], 0) end
    return result[2]
  end)
end

local function start()
  fresh()
  paw.diagnostic.reset()
  local s = qf.stack()
  s.lists, s.at = {}, 0
  paw.keymap.feed("<Esc><Esc>")
  paw.ui.focus("arrange")
end

local function screen() return table.concat(api.ui_snapshot(W, H), "\n") end

local function ex(line) return paw.commands.exec(line) end

local keys = T.keys

-- Two parts, a clip of notes on the first, a synth on the second.
local function song()
  local a = paw.add_part({ name = "Oboe" })
  local clip = a:add_clip({
    start = 4,
    length = 4,
    name = "tune",
    notes = {
      { pitch = 60, start = 0, length = 1 },
      { pitch = 100, start = 2, length = 1 },
    },
  })
  local b = paw.add_part({ name = "Bass" })
  local synth = b:add_device("synth")
  return a, b, clip, synth
end

test("qf: ]q [q ]Q [Q go through a list from Lua, to each entry's place, stopping at the ends", function()
  start()
  local a, b, clip = song()
  local notes = clip:notes()
  qf.set({
    { address = A.part(a.id), selector = { time = { 12, 12 } }, text = "too quiet here", level = "warning" },
    { address = A.note(clip.id, notes[2].id), text = "out of range", level = "error", source = "tests" },
    { address = A.part(b.id), text = "nothing plays" },
  }, { title = "Mine" })
  eq(qf.current().title, "Mine", "the list is current")
  keys("]q")
  eq(
    paw.ui.focused .. " " .. paw.cursor.part_id() .. " " .. paw.cursor.beat,
    "arrange " .. a.id .. " 12",
    "the first ]q goes to the first entry"
  )
  keys("]q")
  local roll = paw.ui.views:get("pianoroll")
  eq(
    paw.ui.focused .. " " .. tostring(roll.clip_id) .. " " .. roll.beat .. " " .. roll.pitch,
    "pianoroll " .. clip.id .. " 2 100",
    "a note's entry opens its clip in the piano roll, the cursor on it"
  )
  keys("]q")
  eq(paw.cursor.part_id(), b.id, "a part's")
  keys("]q")
  eq(qf.current().idx, 3, "]q stops at the last")
  keys("[Q")
  eq(qf.current().idx, 1, "[Q goes to the first")
  keys("]Q")
  eq(qf.current().idx, 3, "]Q to the last")
  keys("2[q")
  eq(qf.current().idx, 1, "a count steps further")
  ex("cc 2")
  eq(qf.current().idx, 2, ":cc 2")
  ex("cnext")
  eq(qf.current().idx, 3, ":cnext")
  ex("cprev")
  eq(qf.current().idx, 2, ":cprev")
  ex("clast")
  ex("cfirst")
  eq(qf.current().idx, 1, ":clast, :cfirst")
end)

test("qf: the status line counts the list's entries by level while it has some", function()
  start()
  local a = paw.add_part({ name = "Oboe" })
  eq(screen():find("qf ", 1, true), nil, "nothing while there is no list")
  qf.set({
    { address = A.part(a.id), text = "one", level = "error" },
    { address = A.part(a.id), text = "two", level = "warning" },
    { address = A.part(a.id), text = "three", level = "warning" },
  }, { title = "Mine" })
  eq(screen():find("qf E1 W2", 1, true) ~= nil, true, "qf E1 W2\n" .. screen())
  ex("cc 2")
  eq(screen():find("qf 2/3 E1 W2", 1, true) ~= nil, true, "with the position once one has been gone to")
  qf.set({}, { title = "Mine" })
  eq(screen():find("qf ", 1, true), nil, "and nothing once it is empty")
end)

test("qf: :copen docks the list along the bottom; j and Enter go to an entry in the view that shows it", function()
  start()
  local a, _, clip, synth = song()
  local lane = a:automate("volume")
  lane:set_points({ { 0, -6 }, { 6, -3 } })
  paw.flush()
  qf.set({
    { address = A.clip(clip.id), text = "the clip" },
    { address = A.param(synth.id, "cutoff"), text = "the cutoff", level = "warning" },
    { address = A.lane(lane.id), selector = { time = { 6, 6 } }, text = "a point" },
    { address = A.project(), selector = { time = { 16, 16 } }, text = "bar 5" },
  }, { title = "Places" })
  ex("copen")
  local cur = L.current()
  eq(cur.view, "qflist", "the list's window has the keyboard")
  local rects = {}
  for _, r in ipairs(paw.ui.arrange(W, H)) do
    rects[r.name] = r
  end
  eq(rects.qflist.w, W, "the whole width")
  eq(rects.qflist.h, paw.opt.qf_height, "qf_height rows")
  eq(rects.qflist.y > rects.arrange.y, true, "below the arrange view")
  local text = screen()
  eq(text:find("Quickfix list · Places", 1, true) ~= nil, true, "its title\n" .. text)
  eq(text:find("the cutoff", 1, true) ~= nil, true, "and entries")
  eq(
    text:find("Bass › Synth · Cutoff", 1, true) ~= nil or text:find("Bass › Synth", 1, true) ~= nil,
    true,
    "where each is"
  )
  keys("j<CR>")
  eq(paw.ui.focused, "devices", "Enter on a parameter goes to the device panel")
  local row = paw.ui.views:get("devices"):rows()[paw.ui.views:get("devices").row]
  eq(row.param and row.param.key, "cutoff", "on the parameter")
  eq(qf.current().idx, 2, "which becomes the current entry")
  ex("copen")
  eq(L.current().view, "qflist", ":copen again goes to the window it has")
  keys("j<CR>")
  eq(
    paw.ui.focused .. " " .. paw.cursor.part_id() .. " " .. tostring(paw.cursor.lane_id()) .. " " .. paw.cursor.beat,
    "arrange " .. a.id .. " " .. lane.id .. " 6",
    "a lane's point: its row in the arrange view, at the point"
  )
  ex("copen")
  keys("G<CR>")
  eq(paw.cursor.beat, 16, "a bar of the project")
  ex("copen")
  keys("gg<CR>")
  eq(paw.ui.focused .. " " .. paw.cursor.beat, "arrange 4", "a clip: in the arrange view, where it starts")
  ex("cclose")
  for _, r in ipairs(paw.ui.arrange(W, H)) do
    eq(r.name ~= "qflist", true, ":cclose closes it")
  end
  ex("cwindow")
  eq(L.current().view, "qflist", ":cwindow opens it while there are entries")
  qf.set({}, { title = "Places" })
  ex("cwindow")
  eq(L.current().view ~= "qflist", true, "and closes it when there are none")
end)

test("qf: the list is a buffer: :vs quickfix shows it beside, q closes it", function()
  start()
  local a = paw.add_part({ name = "Oboe" })
  qf.set({ { address = A.part(a.id), text = "here" } }, { title = "Mine" })
  ex("vs quickfix")
  local names = {}
  for _, r in ipairs(paw.ui.arrange(W, H)) do
    if r.win then names[#names + 1] = r.name end
  end
  eq(table.concat(names, " "), "arrange qflist", "beside the arrange view")
  eq(screen():find("here", 1, true) ~= nil, true, "showing the entry")
  keys("q")
  names = {}
  for _, r in ipairs(paw.ui.arrange(W, H)) do
    if r.win then names[#names + 1] = r.name end
  end
  eq(table.concat(names, " "), "arrange", "q closes the window")
end)

test("qf: lists keep a history: :colder and :cnewer, one of the same title replaced where it is", function()
  start()
  local a = paw.add_part({ name = "Oboe" })
  qf.set({ { address = A.part(a.id), text = "first" } }, { title = "One" })
  qf.set({ { address = A.part(a.id), text = "second" }, { address = A.part(a.id), text = "more" } }, { title = "Two" })
  eq(qf.current().title, "Two", "the newest is current")
  ex("colder")
  eq(qf.current().title, "One", ":colder")
  ex("cnewer")
  eq(qf.current().title, "Two", ":cnewer")
  ex("cc 2")
  qf.set({ { address = A.part(a.id), text = "new" }, { address = A.part(a.id), text = "more" } }, { title = "Two" })
  eq(
    #qf.stack().lists .. " " .. qf.current().idx,
    "2 2",
    "the same title is replaced in place, the entry it was on kept"
  )
  ex("colder")
  qf.set({ { address = A.part(a.id), text = "third" } }, { title = "Three" })
  eq(#qf.stack().lists, 2, "a new list after an older one drops the newer, as in Neovim")
  for i = 1, 12 do
    qf.set({}, { title = "L" .. i })
  end
  eq(#qf.stack().lists, qf.HISTORY, "ten are kept")
end)

test("qf: diagnostics feed Problems; :cdiag makes a list of them; :cfix makes the fixes as one undo step", function()
  start()
  local _, _, clip = song()
  local list = {}
  for place, n in ipairs(clip:notes()) do
    if n.pitch > 84 then
      list[#list + 1] = {
        notes = { place },
        severity = "error",
        rule = "range",
        message = "too high",
        fixes = { { title = "Down an octave", edits = { { note = place, pitch = n.pitch - 12 } } } },
      }
    end
  end
  paw.diagnostic.set("range", clip, list)
  paw.diagnostic.set("hints", clip, { { at = 0, length = 4, message = "a hint", severity = "hint" } })
  local problems = qf.current()
  eq(problems and problems.title, qf.PROBLEMS, "Problems is made, and current while nothing else is")
  eq(#problems.entries, 1, "with what is worse than a hint (qf_diagnostics)")
  eq(
    problems.entries[1].text .. " " .. problems.entries[1].source,
    "range: too high range",
    "as the diagnostic says it"
  )
  ex("cdiag")
  eq(qf.current().title .. " " .. #qf.current().entries, "Diagnostics 2", ":cdiag lists every one")
  ex("cdiag error")
  eq(#qf.current().entries, 1, "or those this severe")
  api.undo_checkpoint()
  ex("cfix")
  api.undo_checkpoint()
  eq(clip:notes()[2].pitch, 88, "the fix is made")
  eq(#qf.fed("diagnostic"), 1, "Problems follows the diagnostics")
  paw.undo()
  eq(clip:notes()[2].pitch, 100, "one undo takes it back")
  paw.diagnostic.reset()
  eq(#qf.fed("diagnostic"), 0, "and empties with them")
end)

test("qf: :cdo runs a command on each entry and :cfdo once a part, each as one undo step", function()
  start()
  local parts = {}
  for i = 1, 3 do
    parts[i] = paw.add_part({ name = "T" .. i })
  end
  local clip = parts[1]:add_clip({ start = 0, length = 4, notes = {} })
  qf.set({
    { address = A.part(parts[1].id), text = "a" },
    { address = A.clip(clip.id), text = "b" },
    { address = A.part(parts[3].id), text = "c" },
  }, { title = "Parts" })
  api.undo_checkpoint()
  ex("cfdo part.mute")
  api.undo_checkpoint()
  eq(
    tostring(parts[1].mute) .. " " .. tostring(parts[2].mute) .. " " .. tostring(parts[3].mute),
    "true false true",
    ":cfdo mutes each part once"
  )
  paw.undo()
  eq(tostring(parts[1].mute) .. " " .. tostring(parts[3].mute), "false false", "one undo takes it back")
  local seen = {}
  paw.command("qf.test.target", function(ctx) seen[#seen + 1] = ctx.target end, { desc = "Note the target" })
  ex("cdo qf.test.target")
  eq(
    table.concat(seen, " "),
    A.part(parts[1].id) .. " " .. A.clip(clip.id) .. " " .. A.part(parts[3].id),
    ":cdo gives each entry's address as the target"
  )
  eq(qf.current().idx, 3, "and leaves the last current")
  ex("cdo part.solo")
  api.undo_checkpoint()
  eq(tostring(parts[1].solo), "false", "the clip's entry is on its part too: solo twice")
  paw.undo()
  eq(tostring(parts[3].solo), "false", "one undo")
end)

test("qf: location lists are each window's own: :ldiag, :lopen below it, :lnext", function()
  start()
  local _, _, clip = song()
  paw.diagnostic.set("range", clip, { { notes = { 2 }, severity = "error", message = "too high" } })
  local roll = paw.ui.views:get("pianoroll")
  roll:edit(clip)
  paw.ui.focus("pianoroll")
  local win = L.current()
  ex("ldiag")
  eq(#qf.loc_stack(win.id).lists[1].entries, 1, ":ldiag lists what the piano roll's clip has")
  eq(qf.current().title, qf.PROBLEMS, "the quickfix lists are left alone")
  ex("lopen")
  local cur = L.current()
  eq(cur.view .. " " .. L.buf_of(cur).name, "qflist loclist " .. win.id, "its window shows that list")
  ex("lnext")
  eq(
    paw.ui.focused .. " " .. roll.beat .. " " .. roll.pitch,
    "pianoroll 2 100",
    ":lnext from the list's window uses its list"
  )
  paw.ui.focus("arrange")
  ex("lnext")
  eq(paw.ui.focused, "arrange", "a window without one has none")
end)

test("qf: renders that clip, are too loud or fail are problems, with a fix to render again", function()
  start()
  local t = T.tone("loud", 4)
  t.volume = 24
  local info = T.render({ ["end"] = 4, tail = 0, bits = 16 })
  paw.flush()
  local entries = qf.fed("render")
  eq(#entries >= 1, true, "a render that clips is listed")
  eq(entries[1].level .. " " .. entries[1].address, "error " .. A.render(info.path), "as an error about the file")
  eq(entries[1].text:find("over full scale", 1, true) ~= nil, true, entries[1].text)
  eq(qf.fix_title(entries[1]):find("again", 1, true) ~= nil, true, "its fix renders it again")
  t.volume = -12
  T.render({ ["end"] = 4, tail = 0, bits = 16 })
  paw.flush()
  eq(#qf.fed("render"), 1, "each file has its own")
  paw.emit("render.failed", { path = "/nowhere/x.wav", error = "the disk is full" })
  local said
  for _, e in ipairs(qf.fed("render")) do
    if e.address == A.render("/nowhere/x.wav") then said = e.text end
  end
  eq(said, "render of x.wav failed: the disk is full", "a failed render")
end)

test("qf: missing sound files, stopped plugins and plugin files that fail are problems", function()
  start()
  local dir = T.scratch .. "/qfmedia"
  os.execute("mkdir -p '" .. dir .. "/media'")
  local s = {}
  for i = 1, 4800 do
    s[i] = 0.1
  end
  local t = paw.add_part({ name = "Drums" })
  t:add_clip({ file = T.write_wav(dir .. "/media/kick.wav", s), start = 0, length = 2, name = "kick" })
  paw.project.save(dir .. "/song.json")
  os.rename(dir .. "/media/kick.wav", dir .. "/media/moved.wav")
  api.warnings()
  paw.project.load(dir .. "/song.json")
  paw.flush()
  local media = qf.fed("media")
  eq(#media, 1, "the clip playing a missing file")
  eq(media[1].text, "kick plays kick.wav, which is not there", media[1].text)
  eq(media[1].address, A.clip(paw.parts()[1]:clips()[1].id), "about its clip")

  api.test_devices()
  local bad = paw.parts()[1]:add_device("test.panic")
  bad:set("fail", 1)
  paw.transport.play()
  local waited = 0
  while #qf.fed("plugins") == 0 and waited < 5000 do
    advance(100)
    waited = waited + 100
  end
  paw.transport.stop()
  local plugins = qf.fed("plugins")
  eq(#plugins, 1, "a plugin that stopped")
  eq(plugins[1].address, A.device(bad.id), "about the device")
  eq(qf.fix_title(plugins[1]):find("again", 1, true) ~= nil, true, "with a fix that starts it again")
  bad:set("fail", 0)
  qf.fix(plugins)
  paw.flush()
  eq(#qf.fed("plugins"), 0, "fixed, it is no longer listed")

  paw.emit("plugins.scanned", { notes = { "/usr/lib/clap/broken.clap: no entry point" } })
  local scan = qf.fed("plugin scan")
  eq(#scan .. " " .. scan[1].fix, "1 plugins.rescan broken", "a plugin file that could not be looked into")
  local problems = qf.current()
  eq(problems.title, qf.PROBLEMS, "all in Problems")
  eq(problems.entries[1].level, "error", "the worst first")
end)

test("qf: any extension feeds Problems, and the window shows the list in a window of its own", function()
  start()
  local a = paw.add_part({ name = "Oboe" })
  qf.feed("tests", { { address = A.part(a.id), text = "from an extension", level = "info" } })
  eq(qf.current().title, qf.PROBLEMS, "Problems")
  eq(qf.current().entries[1].source, "tests", "the source named")
  local openable = {}
  for _, v in ipairs(paw.canvas.openable()) do
    openable[v.name] = true
  end
  eq(openable.qflist, true, "More lists it")
  ex("qf.window")
  local windows = paw.frontend.state(-1).modal.windows
  local found
  for _, w in ipairs(windows) do
    if w.name == "qflist" then found = w end
  end
  eq(found and found.cells, true, "it opens in a window, drawn in cells")
  local snap = api.ui_view_snapshot("qflist", 100, 8)
  local text = {}
  for _, row in ipairs(snap.rows) do
    local parts = {}
    for _, run in ipairs(row) do
      parts[#parts + 1] = run.text
    end
    text[#text + 1] = table.concat(parts)
  end
  eq(table.concat(text, "\n"):find("from an extension", 1, true) ~= nil, true, table.concat(text, "\n"))
  paw.keymap.feed("<CR>")
  eq(paw.cursor.part_id(), a.id, "Enter in it goes to the entry")
end)

test("qf: ]q and [q do not take the piano roll's ] and [ away", function()
  start()
  local _, _, clip = song()
  paw.ui.views:get("pianoroll"):edit(clip)
  paw.ui.focus("pianoroll")
  paw.ui.views:get("pianoroll"):set(100, 2)
  local before = clip:notes()[2].velocity
  keys("]")
  advance(paw.opt.timeoutlen + 300)
  eq(clip:notes()[2].velocity, math.min(127, before + 10), "] alone still makes the note louder, after the wait")
end)
