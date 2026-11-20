-- The leader's list of keys in every view, ghost examples in an empty popover,
-- panes that keep the arrange view its share, `,p` with no clip open, and
-- help that lands on a one-line entry for a key. Loaded by tests/suite.lua.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local paw = require("paw")
local api = paw.api
local L = paw.layout

local initial = L.capture()

local function hint_of(key)
  for _, hint in ipairs(paw.keymap.hints() or {}) do
    if hint.key == key then return hint.desc end
  end
end

local function load()
  if not package.loaded["notation.keys"] then paw.ext.load("extensions/notation") end
  return require("notation")
end

--- A clip open as notation, the cursor in it.
local function song()
  fresh()
  while paw.ui.float do paw.ui.close() end
  -- A view another test left in a window of its own is not drawn in the terminal.
  for name in pairs(paw.canvas.open_views) do paw.canvas.close(name) end
  L.restore(initial)
  local view = load()
  local track = paw.add_track({ name = "Lead" })
  track:add_device("synth")
  local notes = {}
  for i, p in ipairs({ 60, 62, 64, 65 }) do notes[i] = { pitch = p, start = i - 1, length = 1, velocity = 80 } end
  local clip = track:add_clip({ start = 0, length = 4, name = "tune", notes = notes })
  paw.flush()
  paw.keymap.set_mode("n")
  view:edit(clip)
  return view
end

local function screen() return table.concat(api.ui_snapshot(140, 40), "\n") end

local function rows_with(text)
  local rows = {}
  for i, line in ipairs(api.ui_snapshot(140, 40)) do
    if line:find(text, 1, true) then rows[#rows + 1] = i end
  end
  return rows
end

test("leader: in the notation view the local leader lists the popovers by name, and , lists the global keys", function()
  local view = song()
  local hints, wait = paw.opt.hint_delay, paw.opt.timeoutlen
  T.after(function() paw.opt.hint_delay, paw.opt.timeoutlen = hints, wait; paw.keymap.feed("<Esc>") end)
  paw.opt.hint_delay, paw.opt.timeoutlen = 20, 100
  paw.keymap.feed("<localleader>")
  paw.wait(400)
  eq(paw.keymap.pending(), paw.opt.localleader, "still waiting, the list is on")
  for _, key in ipairs({ "d", "t", "k", "m", "q", "l" }) do
    eq((hint_of(key) or ""):match("^Popover: %a+") ~= nil, true, paw.opt.localleader .. key .. " is listed as a popover")
  end
  eq(hint_of("d"):match("^Popover: dynamics") ~= nil, true, "with its name")
  paw.keymap.feed("<Esc>")
  eq(paw.keymap.pending(), "", "Escape drops it")
  -- The leader is the global one here: no popover on it.
  paw.keymap.feed(",")
  paw.wait(400)
  eq(paw.keymap.pending(), ",", "the leader waits, with its list")
  eq((hint_of("d") or ""):match("^Popover") == nil, true, ",d is not a popover")
  eq(hint_of("m") ~= nil, true, "and the mixer is on it")
  paw.keymap.feed("<Esc>")
  -- A key no leader map has: the motion runs, then the key is a command of its own.
  view:set(nil, 2)
  paw.keymap.feed("fe")
  local at = view.beat
  paw.keymap.feed(",")
  paw.keymap.feed("<Esc>")
  eq(paw.keymap.pending(), "", "nothing left half typed")
  eq(at ~= nil, true, "the cursor is somewhere")
end)

test("leader: , m in the notation view is the mixer, as everywhere", function()
  local view = song()
  T.after(function() paw.ui.hide("mixer") end)
  paw.ui.hide("mixer")
  paw.keymap.feed(",m")
  paw.wait(50)
  eq(paw.ui.visible("mixer"), true, ",m reaches the global leader key in the notation view")
  eq(view.popover.active(), false, "and no popover opened")
end)

test("leader: , in the notation view still goes back along an f after a pause, with no list to read", function()
  local view = song()
  local wait, hints = paw.opt.timeoutlen, paw.opt.hints
  T.after(function() paw.opt.timeoutlen, paw.opt.hints = wait, hints end)
  paw.opt.timeoutlen, paw.opt.hints = 20, false
  view:set(nil, 0)
  paw.keymap.feed("fe")
  local after_f = view.beat
  paw.keymap.feed(",")
  paw.wait(300)
  eq(paw.keymap.pending(), "", "the wait ended")
  eq(view.beat < after_f or view.beat == after_f, true, "and , went the other way, or stayed")
end)

test("popover: an empty prompt shows examples, and Tab fills the line", function()
  local view = song()
  local wait = paw.opt.timeoutlen
  T.after(function() paw.opt.timeoutlen = wait end)
  paw.opt.timeoutlen = 20
  paw.keymap.feed("<localleader>d")
  paw.wait(150)
  eq(#rows_with("pp p mp mf f ff  mp<f  sfz") > 0, true, "dynamics examples")
  paw.keymap.feed("<Tab>")
  eq(#rows_with("pp p mp mf f ff  mp<f  sfz"), 0, "gone once the line has text")
  paw.keymap.feed("<Esc>")
  for key, ghost in pairs({ t = "Allegro q=132  rit.  a tempo", k = "Eb  f#m  D dorian", m = "6/8  3+3+2/8", q = "Cmaj7  G/B  N.C.",
      l = "syllables, Space next, - hyphen" }) do
    paw.keymap.feed("<localleader>" .. key)
    -- An extension's longer mapping (the pattern's `,t…`) makes the popover wait out `timeoutlen`.
    paw.wait(150)
    eq(#rows_with(ghost) > 0, true, "," .. key .. " shows " .. ghost .. " on\n" .. screen())
    paw.keymap.feed("<Esc>")
  end
end)

test("popover: it sits under the staff, so a tempo mark stays in sight", function()
  local view = song()
  paw.keymap.feed("<localleader>tAllegro q=132")
  local rows = rows_with("Allegro")
  eq(#rows >= 2, true, "the mark on the staff and the text in the prompt are both on the screen")
  paw.keymap.feed("<Esc>")
end)

test("panes: the arrange view keeps two fifths of a column with a roll, notation, quickfix and a curve", function()
  fresh()
  local tree = { dir = "v", L.leaf("arrange"), L.leaf("pianoroll", { weight = 2 }), L.leaf("notation", { weight = 2 }),
    L.leaf("qflist", { size = 10 }), L.leaf("curve", { size = 8 }) }
  local rects = paw.ui.place(tree, 0, 0, 100, 60)
  local arrange
  for _, r in ipairs(rects) do if r.name == "arrange" then arrange = r end end
  eq(arrange.h >= 24, true, "arrange has at least 24 of 60 rows, got " .. arrange.h)
  local sum = 0
  for _, r in ipairs(rects) do sum = sum + r.h end
  eq(sum, 60, "and the rows add up")
end)

test("roll.toggle: with no clip open it opens the clip under the cursor, or says there is none", function()
  fresh()
  paw.ui.hide("pianoroll")
  paw.ui.focus("arrange")
  local before = api.json_encode(paw.ui.arrange())
  paw.commands.exec("roll.toggle")
  eq(paw.ui.visible("pianoroll"), false, "no pane opened")
  eq(api.json_encode(paw.ui.arrange()), before, "the layout is as it was")
  eq((paw.ui.message and paw.ui.message.text or ""):match("no clip") ~= nil, true, "the message line says so")
  local track = paw.add_track({ name = "Lead" })
  local clip = track:add_clip({ start = 0, length = 4, name = "tune", notes = { { pitch = 60, start = 0, length = 1, velocity = 80 } } })
  paw.flush()
  paw.cursor.set_track(track)
  paw.cursor.set_beat(1)
  paw.commands.exec("roll.toggle")
  eq(paw.ui.visible("pianoroll"), true, "with a clip under the cursor the roll is shown")
  eq(paw.ui.views.pianoroll:clip() ~= nil, true, "on that clip")
  paw.commands.exec("roll.toggle")
  eq(paw.ui.visible("pianoroll"), false, "and again hides it")
end)

test("help: a key's entry is its row in the key table, and the help split takes half the screen", function()
  fresh()
  local initial = L.capture()
  T.after(function()
    for _, buf in ipairs(L.buffers_list()) do
      if buf.type == "textbuf" then L.buf_delete(buf) end
    end
    L.restore(initial)
    paw.ui.focus("arrange")
  end)
  paw.help.open("gL")
  local _, buf, t, s = paw.textbuf.here()
  eq(buf.name, "help://keys.md", "the key table's page")
  eq(t:line(s.row):match("^%s*|") ~= nil or t:line(s.row):match("gL") ~= nil, true, "on a line that names the key")
  eq(#t:line(s.row) < 120, true, "a one-line entry, not a paragraph")
  local _, height = paw.ui.size()
  for _, r in ipairs(paw.ui.arrange()) do
    if r.name == "textbuf" then eq(r.h >= math.floor(height / 2) - 1, true, "help has about half of " .. height .. ", got " .. r.h) end
  end
end)
