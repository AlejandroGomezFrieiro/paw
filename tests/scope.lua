-- Tests of narrowing to a group (paw.scope), freezing tracks and groups
-- (paw.freeze, crates/paw-core/src/freeze.rs) and stems by group
-- (paw.stems). Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, near, fails, fresh = T.test, T.eq, T.near, T.fails, T.fresh
local api = paw.api
local ffi = require("ffi")
local L = paw.layout

local W, H = 160, 48

local initial = L.capture()

local function reset()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do paw.ui.close() end
  L.restore(initial)
  paw.opt.scope_rest = "play"
  paw.ui.focus("arrange")
end

local function start()
  fresh()
  api.engine_restart({ backend = "null" })
  reset()
end

local keys = T.keys

local function screen() return table.concat(api.ui_snapshot(W, H), "\n") end

local function names(ids)
  local out = {}
  for i, id in ipairs(ids) do out[i] = api.track_get(id).name end
  return table.concat(out, " ")
end

local function wait_for(what, limit, fn)
  local waited = 0
  while not fn() do
    if waited >= limit then error("waited " .. limit .. " ms for " .. what, 2) end
    paw.wait(20)
    waited = waited + 20
  end
end

--- A track with a synth playing a few notes.
local function synth(name, pitch)
  local t = paw.add_track({ name = name })
  t:add_device("synth", { attack = 0.001, release = 0.05 })
  t:add_clip({ start = 0, length = 4, notes = {
    { pitch = pitch, start = 0, length = 1 }, { pitch = pitch + 4, start = 1, length = 1 }, { pitch = pitch + 7, start = 2, length = 2 },
  } })
  return t
end

--- Orchestra holding Strings (Violins, Cellos) and Brass (Horns); Drums
--- outside it.
local function orchestra()
  local violins, cellos, horns = synth("Violins", 72), synth("Cellos", 48), synth("Horns", 60)
  local drums = synth("Drums", 36)
  local strings = paw.groups.make({ violins, cellos }, "Strings")
  local brass = paw.groups.make({ horns }, "Brass")
  local orch = paw.groups.make({ strings, brass }, "Orchestra")
  paw.flush()
  api.undo_checkpoint()
  return { violins = violins, cellos = cellos, horns = horns, drums = drums, strings = strings, brass = brass, orchestra = orch }
end

--- The samples of a 32-bit float WAV file written by `paw.render`.
local function samples(path)
  local data = T.read_file(path)
  local at = data:find("data", 1, true)
  local n = (#data - (at + 7)) / 4
  local buf = ffi.new("float[?]", n)
  ffi.copy(buf, data:sub(at + 8), n * 4)
  return buf, n
end

--- The largest difference between two float WAV files, sample by sample,
--- and the larger file's peak.
local function difference(a, b)
  local x, n = samples(a.path)
  local y, m = samples(b.path)
  local worst, peak = 0, 0
  for i = 0, math.min(n, m) - 1 do
    worst = math.max(worst, math.abs(x[i] - y[i]))
    peak = math.max(peak, math.abs(x[i]))
  end
  return worst, peak, n, m
end

local renders = 0
local function render(opts)
  renders = renders + 1
  return paw.render(T.scratch .. "/scope" .. renders .. ".wav", paw.util.merge({ bits = 32, tail = 1 }, opts or {}))
end

-- Narrowing ---------------------------------------------------------------------------

test("narrowing to a group opens a tab of its tracks alone, and widening comes back", function()
  start()
  local o = orchestra()
  paw.cursor.set_track(o.drums)
  paw.scope.narrow("Strings")
  eq(#paw.ui.tabs, 2, "a tab of its own")
  eq(paw.ui.tab, 2, "gone to")
  eq(L.tab_title(paw.ui.tabs[2]), "Strings", "named after the group")
  eq(names(paw.groups.rows()), "Strings Violins Cellos", "the arrange view's rows")
  eq(paw.cursor.track_id(), o.strings.id, "the cursor came inside")
  local text = screen()
  eq(text:find("Violins", 1, true) ~= nil and text:find("Horns", 1, true) == nil and text:find("Drums", 1, true) == nil, true,
    "drawn: only the strings")
  eq(text:find("Song › Strings", 1, true) ~= nil, true, "the status line says so")
  -- The rest of the program sees the scope too.
  local items = paw.pick.sources.tracks.items()
  eq(#items, 3, "the track picker lists its tracks")
  eq(names(paw.scope.tracks()), "Strings Violins Cellos", "paw.scope.tracks")
  paw.ui.show("mixer")
  eq(screen():find("Horns", 1, true), nil, "the mixer has no strip for the rest")
  paw.ui.hide("mixer")
  -- Motions stay inside.
  keys("G")
  eq(paw.cursor.track_id(), o.cellos.id, "G: the last track of the scope")
  keys("gg")
  eq(paw.cursor.track_id(), o.strings.id, "gg: the first")
  -- Folding the group itself does not empty its tab.
  paw.groups.fold(o.strings.id, true)
  eq(names(paw.groups.rows()), "Strings Violins Cellos", "the scope's own fold is open in it")
  paw.groups.fold(o.strings.id, false)
  -- Back out.
  eq(paw.scope.widen(), true, "widened")
  eq(#paw.ui.tabs, 1, "the tab closed")
  eq(paw.scope.current(), nil, "no scope")
  eq(#paw.groups.rows(), 7, "every track again")
  reset()
end)

test("zn narrows to the group at the cursor and zw widens; scopes open side by side in tabs", function()
  start()
  local o = orchestra()
  paw.cursor.set_track(o.violins)
  keys("zn")
  eq(paw.scope.group(), o.strings.id, "zn on a member: its group")
  local seen = paw.frontend.revision
  keys("gt")
  eq(paw.frontend.revision > seen, true, "a window is told to draw the other tab's tracks")
  eq(paw.scope.current(), nil, "the first tab is wide")
  eq(#paw.groups.rows(), 7, "and shows everything")
  paw.cursor.set_track(o.brass)
  keys("zn")
  eq(#paw.ui.tabs, 3, "a second scope, in a tab of its own")
  eq(names(paw.groups.rows()), "Brass Horns", "the brass")
  paw.scope.narrow("Strings")
  eq(#paw.ui.tabs, 3, "narrowing to a group that has a tab goes there")
  eq(paw.scope.group(), o.strings.id, "the strings' tab")
  eq(names(paw.groups.rows()), "Strings Violins Cellos", "with its rows")
  keys("zw")
  eq(#paw.ui.tabs, 2, "zw closed it")
  eq(paw.scope.current(), nil, "back in the wide tab")
  reset()
end)

test("in a scope Ex ranges, :g and :s see only its tracks", function()
  start()
  local o = orchestra()
  paw.scope.narrow("Strings")
  local function range(text) return names(paw.ex.range(text).tracks) end
  eq(range("t*"), "Strings Violins Cellos", "t*")
  eq(range("t2"), "Violins", "t2 is the scope's second track")
  eq(range("t$"), "Cellos", "t$ its last")
  eq(range("t/o/"), "Violins Cellos", "t/o/ searches the scope's names")
  local _, _, err = paw.ex.range("t5")
  eq(tostring(err):find("3 tracks", 1, true) ~= nil, true, "t5 is past its end: " .. tostring(err))
  keys(":%s/c3/d3/<CR>")
  paw.flush()
  local function first(t) return t:clips()[1]:notes()[1].pitch end
  eq(first(o.cellos), 50, ":%s changed the scope's notes")
  eq(first(o.drums), 36, "and not the rest's")
  keys(":g/c4/d<CR>")
  eq(#o.horns:clips()[1]:notes(), 3, ":g finds nothing in the scope to delete: the horns' C4 is outside it")
  keys(":g/c5/d<CR>")
  eq(#o.violins:clips()[1]:notes(), 2, ":g/c5/d deletes the violins' C5")
  reset()
end)

test("a track added in a scope goes into its group; one undo tree across the tabs", function()
  start()
  local o = orchestra()
  paw.scope.narrow("Strings")
  local violas = paw.add_track({ name = "Violas" })
  paw.flush()
  paw.wait(20)
  eq(paw.groups.of(violas.id), o.strings.id, "the new track is in Strings")
  eq(names(paw.groups.rows()), "Strings Violins Cellos Violas", "and in sight")
  api.undo_checkpoint()
  o.violins.name = "First violins"
  api.undo_checkpoint()
  paw.scope.widen()
  paw.undo()
  eq(o.violins.name, "Violins", "the rename made in the scope is undone from outside it")
  paw.undo()
  eq(pcall(api.track_get, violas.id), false, "and so is the track added there")
  reset()
end)

test("paw://tracks in a scope lists its tracks, and writing it leaves the rest alone", function()
  start()
  local o = orchestra()
  -- A buffer an earlier test read is forgotten, so that this one reads afresh.
  local function forget()
    for _, buf in ipairs(L.buffers_list()) do
      if buf.type == "textbuf" then L.buf_delete(buf) end
    end
  end
  forget()
  T.after(forget)
  -- One read wide is read again in the narrowed tab.
  keys(":e paw://tracks<CR>")
  keys(":b arrange<CR>")
  paw.scope.narrow("Strings")
  keys(":e paw://tracks<CR>")
  local lines = {}
  for i, l in ipairs(paw.textbuf.buf().state.text.lines) do lines[i] = l.text end
  local text = table.concat(lines, "\n")
  eq(text:find("Violins", 1, true) ~= nil and text:find("Horns", 1, true) == nil, true, "only the strings: " .. text)
  -- Rename the cellos and write: the rest keeps its tracks and their order.
  keys("G0")
  keys("cw\"Basses\"<Esc>")
  keys(":w<CR>")
  keys("y")
  eq(o.cellos.name, "Basses", "renamed")
  eq(names(api.track_list()), "Orchestra Strings Violins Basses Brass Horns Drums", "the rest as it was")
  reset()
end)

-- Scopes of time ---------------------------------------------------------------------------

local function said() return paw.ui.message and paw.ui.message.text or "" end

--- The orchestra, a long drum clip, and a region Bridge over bars 17-24
--- in 6/8 (the song is in 4/4 before and after). Returns its beats too.
local function bridge()
  local o = orchestra()
  o.drums:add_clip({ start = 40, length = 80, notes = { { pitch = 36, start = 0, length = 1 } } })
  keys(":timesig 6/8 at 17<CR>")
  keys(":timesig 4/4 at 25<CR>")
  local from, to = paw.time.bar_start(17), paw.time.bar_start(25)
  paw.markers.add(from, "Bridge", { length = to - from })
  paw.flush()
  return o, from, to
end

test(":narrow on a region shows its time: bars from 1 in its meter, the cursor kept in it, its loop", function()
  start()
  local o, from, to = bridge()
  eq(to - from, 24, "eight bars of 6/8")
  local edits = api.project_get().edits
  paw.cursor.set_track(o.drums)
  paw.cursor.set_beat(0)
  keys(":narrow Bridge<CR>")
  eq(paw.scope.current().kind, "region", "a scope of the region")
  eq(#paw.ui.tabs, 2, "in a tab of its own")
  eq(#paw.groups.rows(), 7, "every track")
  eq(paw.cursor.beat, from, "the cursor came into its time")
  local t = api.transport_get()
  eq(t.loop_enabled and t.loop_start == from and t.loop_end == to, true, "the loop is the region")
  local text = screen()
  eq(text:find("Song › Bridge 1.1 (17.1)", 1, true) ~= nil, true, "the status line: the path, and both places")
  eq(text:find("1.1.00", 1, true) ~= nil, true, "the ruler's corner counts from 1")
  eq(text:find("loop 1%D+8%D") ~= nil, true, "the status line's loop in its bars")
  eq(paw.ruler.label(18, from + 3, "RulerBar", from)[1][1], "2", "the song's bar 18 is its bar 2")
  eq(text:find("19%s+20%s+21") ~= nil, true, "a second row has the song's bars:\n" .. text)
  -- Motions stop at its edges.
  keys("$")
  eq(paw.cursor.beat, to, "$: the drums' clip ends after it; the cursor stops at its end")
  keys("0")
  eq(paw.cursor.beat, from, "0: its start")
  keys("20W")
  eq(paw.cursor.beat, to, "W stops at its end")
  -- Bars typed are its own.
  keys("3|")
  eq(paw.cursor.beat, paw.time.bar_start(19), "3| is the song's bar 19")
  eq(screen():find("Song › Bridge 3.1 (19.1)", 1, true) ~= nil, true, "and the status line says both")
  keys(":2<CR>")
  eq(paw.cursor.beat, paw.time.bar_start(18), ":2 is the song's bar 18")
  eq(api.project_get().edits, edits, "nothing in the project changed")
  keys("zw")
  eq(#paw.ui.tabs, 1, "zw closed the tab")
  eq(paw.scope.current(), nil, "the song")
  eq(api.transport_get().loop_enabled, false, "the loop as it was")
  keys("0")
  eq(paw.cursor.beat, 0, "the cursor goes anywhere again")
  reset()
end)

test("a scope inside a scope shows what both show: the strings in the bridge", function()
  start()
  local o, from, to = bridge()
  keys(":narrow Bridge<CR>")
  keys(":narrow Strings<CR>")
  eq(#paw.ui.tabs, 2, "in the same tab")
  eq(paw.scope.breadcrumb(), "Song › Bridge › Strings", "its path")
  eq(names(paw.groups.rows()), "Strings Violins Cellos", "the strings")
  local a, b = paw.scope.span()
  eq(a == from and b == to, true, "in the bridge's time")
  eq(paw.scope.contains(o.drums), false, "not the drums")
  eq(screen():find("Song › Bridge › Strings", 1, true) ~= nil, true, "the status line")
  keys(":narrow Brass<CR>")
  eq(said():find("no track of Brass is in Strings", 1, true) ~= nil, true, "an empty scope is refused: " .. said())
  keys("zw")
  eq(paw.scope.breadcrumb(), "Song › Bridge", "zw: up one level")
  eq(#paw.groups.rows(), 7, "every track again")
  keys(":narrow Strings<CR>")
  keys(":widen!<CR>")
  eq(paw.scope.current(), nil, ":widen! goes up to the song")
  eq(#paw.ui.tabs, 1, "and closes the tab")
  reset()
end)

-- What the rest does ---------------------------------------------------------------------

test("scope_rest=mute silences the rest while the scope's tab is in front", function()
  start()
  local o = orchestra()
  paw.project.tempo = 60
  paw.scope.narrow("Strings")
  paw.opt.scope_rest = "mute"
  paw.transport.seek(0)
  paw.transport.play()
  wait_for("the violins", 3000, function() return select(1, o.violins:meter()) > 0.01 end)
  paw.wait(100)
  eq(select(1, o.drums:meter()) < 1e-4, true, "the drums are silent")
  eq(select(1, o.orchestra:meter()) > 0.01, true, "the group the strings pass through is not")
  keys("gt")
  wait_for("the drums", 3000, function() return select(1, o.drums:meter()) > 0.01 end)
  paw.transport.stop()
  eq(o.drums.mute, false, "the project's mute was not touched")
  reset()
end)

test("scope_rest=frozen plays the rest from files rendered in the background", function()
  start()
  local o = orchestra()
  paw.scope.narrow("Strings")
  local edits = api.project_get().edits
  eq(names(paw.scope.rest_parts()), "Brass Drums", "the parts of the rest: whole groups, not the scope's own")
  paw.opt.scope_rest = "frozen"
  wait_for("the rest to be frozen", 20000, function() return #paw.scope.held() == 2 end)
  table.sort(api.engine_held())
  eq(#api.engine_held(), 2, "the engine plays them from files")
  eq(api.project_get().edits, edits, "the project is not changed")
  keys("gt")
  eq(#api.engine_held(), 0, "a wide tab plays everything live")
  keys("gt")
  eq(#api.engine_held(), 2, "back in the scope, the files are there already")
  -- An edit to a frozen part plays it live until it is rendered again.
  o.horns:clips()[1]:set_notes({ { pitch = 62, start = 0, length = 2 } })
  paw.flush()
  paw.wait(50)
  wait_for("the brass again", 20000, function() return #paw.scope.held() == 2 end)
  paw.scope.widen()
  eq(#api.engine_held(), 0, "widening lets it go")
  reset()
end)

-- Freezing -----------------------------------------------------------------------------

test("a frozen track renders as it did live, and its fader stays live", function()
  start()
  local t = synth("Lead", 60)
  t:add_device("delay", {})
  paw.flush()
  local live = render()
  paw.freeze.freeze(t)
  eq(paw.freeze.state(t), "frozen", "frozen")
  eq(#t:clips(), 1, "its clips are as they were")
  local frozen = render()
  local worst, peak = difference(live, frozen)
  eq(peak > 0.05, true, "it sounds")
  eq(worst < 1e-5, true, "the same sound, frozen as live: " .. worst)
  t.volume = -6
  local quieter = render()
  near(quieter.peak / frozen.peak, 10 ^ (-6 / 20), 1e-3, "the fader still works")
  reset()
end)

test("a frozen group renders as it did live; its members are held", function()
  start()
  local o = orchestra()
  o.strings:add_device("delay", {})
  o.violins.volume = -3
  paw.flush()
  local live = render()
  paw.freeze.freeze(o.strings)
  eq(paw.freeze.state(o.violins), "held", "a member is held")
  eq(paw.freeze.state(o.strings), "frozen", "the group frozen")
  local worst, peak = difference(live, render())
  eq(peak > 0.05, true, "it sounds")
  eq(worst < 1e-5, true, "the song is the same: " .. worst)
  fails(function() paw.freeze.freeze(o.violins) end, "unfreeze that first", "a held track is not frozen again")
  -- The group's fader and mute stay live.
  o.strings.mute = true
  local without = render()
  o.strings.mute = false
  local w2 = difference(live, without)
  eq(w2 > 0.01, true, "muting the frozen group takes it out")
  reset()
end)

test("freezing is one undo step and saved with the project, the file beside it", function()
  start()
  local t = synth("Pad", 55)
  paw.flush()
  api.undo_checkpoint()
  local file = paw.freeze.freeze(t)
  api.undo_checkpoint()
  paw.undo()
  eq(paw.freeze.state(t), nil, "undone")
  paw.redo()
  eq(paw.freeze.frozen(t).file, file, "and redone")
  local dir = T.scratch .. "/frozen-project"
  os.execute("mkdir -p '" .. dir .. "'")
  paw.cmd("write", { dir .. "/song" })
  local saved = T.read_file(dir .. "/song/tracks/Pad/track.json")
  eq(saved:find('"media/Pad%-frozen') ~= nil, true, "the file is named relative to the project")
  paw.project.new()
  paw.open(dir .. "/song")
  local pad = paw.track(api.track_list()[1])
  local frozen = paw.freeze.frozen(pad)
  eq(frozen and frozen.file:find("^/") ~= nil and io.open(frozen.file) ~= nil, true, "it opens frozen, the file found")
  paw.freeze.unfreeze(pad)
  eq(paw.freeze.state(pad), nil, ":unfreeze")
  reset()
end)

test(":freeze and :unfreeze, and an edit to a frozen track asks to unfreeze it", function()
  start()
  local t = synth("Keys", 64)
  paw.cursor.set_track(t)
  keys(":freeze<CR>")
  eq(paw.freeze.state(t), "frozen", ":freeze the cursor's track")
  local clip = t:clips()[1]
  clip:set_notes({ { pitch = 70, start = 0, length = 1 } })
  paw.flush()
  paw.wait(20)
  eq(screen():find("Keys is frozen: unfreeze it", 1, true) ~= nil, true, "asked")
  keys("y<CR>")
  eq(paw.freeze.state(t), nil, "y: unfrozen")
  keys(":freeze Keys<CR>")
  eq(paw.freeze.state(t), "frozen", ":freeze by name")
  keys(":unfreeze<CR>")
  eq(paw.freeze.state(t), nil, ":unfreeze")
  reset()
end)

test("a frozen track's heavy Lua device rests: the engine works far less", function()
  start()
  local dir = T.scratch .. "/heavy-devices"
  os.execute("mkdir -p '" .. dir .. "'")
  T.write_file(dir .. "/heavy.lua", [[
local dev = require("paw.dsp").device { name = "Heavy" }
local x = 0
function dev.process(b)
  for i = 0, b.frames - 1 do
    local s = b.left[i]
    for _ = 1, 400 do s = math.sin(s + x) * 0.5 end
    x = x + 1e-7
    b.left[i] = b.left[i] + s * 1e-6
  end
end
return dev
]])
  paw.luadev.add_dir(dir)
  local t = synth("Heavy", 60)
  t:add_device("lua:heavy")
  paw.flush()
  local function load()
    api.engine_reset_stats()
    paw.transport.seek(0)
    paw.transport.play()
    paw.wait(1500)
    paw.transport.stop()
    return api.engine_get().blocks.mean
  end
  local live = load()
  paw.freeze.freeze(t)
  paw.flush()
  local frozen = load()
  print(string.format("      block time: %.3f ms live, %.3f ms frozen", live, frozen))
  eq(frozen < live * 0.3, true, string.format("frozen %.3f ms against %.3f ms a block", frozen, live))
  reset()
end)

-- Stems by group ---------------------------------------------------------------------------

test(":render stems shows a plan of one file per group, and they add up to the mix", function()
  start()
  local o = orchestra()
  paw.flush()
  local mix = render({ master = false })
  local dir = T.scratch .. "/group-stems"
  keys(":render stems " .. dir .. " wait=true bits=32 tail=1<CR>")
  eq(paw.ui.float and paw.ui.float.name, "render.plan", "a plan first")
  local text = screen()
  eq(text:find("Orchestra.wav", 1, true) ~= nil and text:find("Drums.wav", 1, true) ~= nil, true, "a file per group: " .. text)
  eq(text:find("Violins, Cellos, Horns", 1, true) ~= nil, true, "saying what each holds")
  keys("y")
  local a = { path = dir .. "/Orchestra.wav" }
  local b = { path = dir .. "/Drums.wav" }
  eq(io.open(a.path) ~= nil and io.open(b.path) ~= nil, true, "written")
  -- The stems summed are the mix (without the master's processing).
  local x, n = samples(a.path)
  local y = samples(b.path)
  local m, k = samples(mix.path)
  local worst = 0
  for i = 0, math.min(n, k) - 1 do worst = math.max(worst, math.abs(x[i] + y[i] - m[i])) end
  eq(worst < 1e-5, true, "they add up to the mix: " .. worst)
  -- Narrowed, the parts of the group; and one group on its own.
  paw.scope.narrow("Orchestra")
  local plan = paw.stems.plan({ dir = dir })
  local list = {}
  for i, s in ipairs(plan) do list[i] = s.file:match("([^/]+)$") end
  eq(table.concat(list, " "), "Strings.wav Brass.wav", "in a scope: its groups")
  plan = paw.stems.plan({ dir = dir, tracks = true })
  list = {}
  for i, s in ipairs(plan) do list[i] = s.name end
  eq(table.concat(list, " "), "Violins Cellos Horns", "per track")
  paw.scope.widen()
  keys(":render Strings bits=32 wait=true<CR>")
  eq(paw.ui.float and paw.ui.float.name, "render.plan", "one group: a plan too")
  keys("<Esc>")
  eq(paw.ui.float, nil, "Esc leaves it")
  reset()
end)
