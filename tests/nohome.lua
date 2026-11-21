-- Tests of a screen with no home view: any view alone in a tab, a start
-- layout, the start page of an empty window, views opened on a clip by
-- name, docking beside the window with the keyboard, and the tabs and
-- windows a project keeps. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api
local L = paw.layout

local W, H = 160, 48

local initial = L.capture()

local function reset()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do paw.ui.close() end
  paw.ui.start_layout = nil
  L.restore(initial)
  paw.ui.focus("arrange")
end

local function start()
  fresh()
  reset()
  T.after(reset)
end

local function screen() return table.concat(api.ui_snapshot(W, H), "\n") end

--- The names of the windows on screen, in order, bars left out.
local function windows()
  local out = {}
  for _, r in ipairs(paw.ui.arrange(W, H)) do
    if r.win then out[#out + 1] = r.name end
  end
  return table.concat(out, " ")
end

local function rects()
  local out = {}
  for _, r in ipairs(paw.ui.arrange(W, H)) do out[r.name] = r end
  return out
end

local keys = T.keys

--- Run `fn` with the screen of the size the tests draw.
local function sized(fn)
  local size = api.ui_size
  api.ui_size = function() return W, H end
  local ok, err = xpcall(fn, debug.traceback)
  api.ui_size = size
  if not ok then error(err, 0) end
end

local function notation()
  if not package.loaded["notation.keys"] then paw.ext.load("extensions/notation") end
end

local function riff()
  local t = paw.add_track({ name = "Keys" })
  local clip = t:add_clip({ start = 0, length = 8, name = "riff", notes = { { pitch = 60, start = 0, length = 1 }, { pitch = 64, start = 1, length = 1 } } })
  local other = t:add_clip({ start = 8, length = 8, name = "hook", notes = { { pitch = 72, start = 0, length = 2 } } })
  paw.cursor.set_track(t)
  return t, clip, other
end

local function has_arrange()
  for _, tab in ipairs(paw.ui.tabs) do
    for _, win in ipairs(L.windows(tab.layout)) do
      if win.view == "arrange" then return true end
    end
  end
  return false
end

test("nohome: a start layout of the notation alone: one tab, one window, no arrange view", function()
  start()
  notation()
  local _, clip = riff()
  paw.ui.start_layout = "notation://riff"
  L.start()
  eq(#paw.ui.tabs, 1, "one tab")
  eq(windows(), "notation", "the notation, the whole screen")
  eq(paw.ui.focused, "notation", "with the keyboard")
  eq(paw.ui.views.notation.clip_id, clip.id, "on the clip the layout names")
  local r = rects().notation
  eq(r.x == 0 and r.w == W and r.y == 0, true, "full screen")
  eq(screen():find("traceback", 1, true), nil, "drawn")
  eq(has_arrange(), false, "no arrange view in any tab")
end)

test("nohome: closing and toggling never bring the arrange view back", function()
  start()
  notation()
  riff()
  L.restore(L.as_tabs("notation://riff"))
  sized(function()
    keys("<leader>mm")
    eq(windows(), "notation mixer", "Space mm docks the mixer below")
    keys("<leader>mm")
    eq(windows(), "notation", "Space mm again closes it")
    eq(paw.ui.focused, "notation", "the keyboard back in the notation")
    keys(":close<CR>")
    eq(windows(), "notation", ":close in the last window leaves it")
    keys("<C-w>c")
    eq(windows(), "notation", "and Ctrl-w c")
    keys("<C-w>o")
    eq(windows(), "notation", "Ctrl-w o")
    keys("<localleader>n")
    eq(windows(), "notation", "\\n in the only window")
    paw.ui.toggle("notation")
    eq(windows(), "notation", "the toggle of the only window")
    keys(":vs mixer<CR>")
    keys(":view.close<CR>")
    eq(windows(), "notation", ":view.close closes the mixer")
    eq(paw.ui.focused, "notation", "and the keyboard goes to the window before")
    keys(":view.only<CR>")
    eq(windows(), "notation", ":view.only")
  end)
  eq(has_arrange(), false, "the arrange view never came")
end)

test("nohome: an empty tab shows the start page: the transport, recent projects and how to show a view", function()
  start()
  local list = T.scratch .. "/nohome-recent.json"
  os.remove(list)
  paw.recent.use(list)
  T.after(function() paw.recent.use() end)
  local t = paw.add_track({ name = "Bass" })
  t:add_clip({ start = 0, length = 4, notes = { { pitch = 40, start = 0, length = 1 } } })
  local path = T.scratch .. "/nohome-start.json"
  paw.project.save(path)
  paw.project.new()
  paw.flush()
  keys(":tabnew<CR>")
  eq(windows(), "empty", "an empty window")
  local text = screen()
  eq(text:find("Start", 1, true) ~= nil, true, "the start page")
  eq(text:find("stopped at", 1, true) ~= nil, true, "with the transport")
  eq(text:find("Recent projects", 1, true) ~= nil and text:find("nohome-start", 1, true) ~= nil, true, "the project saved last")
  eq(text:find(":tabnew <view>", 1, true) ~= nil and text:find(":e roll://riff", 1, true) ~= nil, true, "and what to type")
  eq(table.concat(paw.ui.keybar.check(), ", "), "", "its keys on the bottom line are mapped")
  keys("<CR>")
  eq(api.project_get().path, path, "Enter opens the project under the cursor")
  eq(#api.track_list(), 1, "with its track")
end)

test("nohome: :e, :vs and :tabnew open a clip in a view by name: roll://riff, roll://7, notation://hook", function()
  start()
  notation()
  local _, clip, other = riff()
  keys(":e roll://riff<CR>")
  eq(windows(), "pianoroll", ":e shows the roll in this window")
  eq(paw.ui.views.pianoroll.clip_id, clip.id, "on the clip of that name")
  keys(":e roll://" .. other.id .. "<CR>")
  eq(paw.ui.views.pianoroll.clip_id, other.id, "or of that number")
  keys(":tabnew notation://hook<CR>")
  eq(#paw.ui.tabs, 2, "a new tab")
  eq(windows(), "notation", "that shows the notation")
  eq(paw.ui.views.notation.clip_id, other.id, "of the clip hook")
  keys(":e roll://nothing<CR>")
  eq(paw.ui.message and paw.ui.message.text:find("no clip", 1, true) ~= nil, true, "a name that is no clip says so")
end)

test("nohome: a view docks beside the window that has the keyboard, as a split in Neovim", function()
  start()
  riff()
  L.restore(L.as_tabs({ dir = "h", "roll://riff", "eventlist" }))
  sized(function()
    paw.ui.focus("pianoroll")
    keys("<leader>mm")
    local r = rects()
    eq(r.mixer.x, r.pianoroll.x, "the mixer under the roll")
    eq(r.mixer.w, r.pianoroll.w, "as wide as the roll")
    eq(r.mixer.y > r.pianoroll.y, true, "below it")
    eq(r.eventlist.h > r.pianoroll.h, true, "the event list keeps its whole height")
    keys("<leader>mm")
    paw.ui.focus("eventlist")
    paw.ui.toggle("devices")
    r = rects()
    eq(r.devices.x > r.eventlist.x, true, "the device panel right of the event list")
  end)
end)

test("nohome: a project keeps its tabs and windows, opens with them, and saving them is no undo step", function()
  start()
  notation()
  riff()
  sized(function()
    keys(":e notation://riff<CR>")
    keys(":vs roll://hook<CR>")
    keys(":tabnew mixer<CR>")
  end)
  local path = T.scratch .. "/nohome-screen.json"
  api.undo_checkpoint()
  local steps = api.undo_current()
  paw.project.save(path)
  api.undo_checkpoint()
  eq(api.undo_current(), steps, "no undo step")
  eq(api.project_get().modified, false, "not modified")
  local text = T.read_file(path)
  eq(text:find('"screen"', 1, true) ~= nil, true, "the file keeps a screen")
  reset()
  eq(windows(), "arrange", "another layout meanwhile")
  paw.open(path)
  paw.flush()
  eq(#paw.ui.tabs, 2, "two tabs again")
  eq(windows(), "mixer", "in the tab that had the keyboard")
  keys("gt")
  eq(windows(), "notation pianoroll", "the notation and the roll side by side")
  local roll, score = paw.ui.views.pianoroll:clip(), paw.ui.views.notation:clip()
  eq(roll and roll.name, "hook", "the roll on its clip")
  eq(score and score.name, "riff", "the notation on its clip")
  paw.opt.project_screen = false
  T.after(function() paw.opt.project_screen = true end)
  reset()
  paw.open(path)
  paw.flush()
  eq(windows(), "arrange", "with project_screen off, the screen stays as it is")
end)

test("nohome: a roll on a clip that was undone keeps no clip: the project opens and saves the same screen", function()
  start()
  local t = riff()
  api.undo_checkpoint()
  paw.cursor.set_beat(16)
  keys("i<CR>")
  keys("4l<Esc>")
  keys("<C-w>p")
  keys("u")
  eq(#t:clips(), 2, "the clip drawn is undone")
  local dir = T.scratch .. "/nohome-undone"
  os.execute("rm -rf '" .. dir .. "'")
  paw.project.save(dir)
  local saved = T.read_file(dir .. "/screen.json")
  reset()
  paw.open(dir .. "/project.toml")
  paw.flush()
  eq(paw.ui.views.pianoroll:clip(), nil, "the roll on no clip, as it was")
  keys(":wa<CR>")
  eq(T.read_file(dir .. "/screen.json"), saved, "a save after open writes the same screen")
end)
