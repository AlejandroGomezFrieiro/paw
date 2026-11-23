-- Tests of a view's state for each window: two piano rolls on two clips,
-- one score twice, the notation beside the piano roll of its clip, and the
-- locators of each window. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api
local L = paw.layout

local W, H = 160, 48

local initial = L.capture()

local function reset()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
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
  local t = paw.add_part({ name = "Keys" })
  local clip = t:add_clip({
    start = 0,
    length = 8,
    name = "riff",
    notes = { { pitch = 60, start = 0, length = 1 }, { pitch = 64, start = 1, length = 1 } },
  })
  local other = t:add_clip({ start = 8, length = 8, name = "hook", notes = { { pitch = 72, start = 0, length = 2 } } })
  paw.cursor.set_part(t)
  return t, clip, other
end

--- What `fn(view)` gives in each window of `name` in the tab, in order.
local function each(name, fn)
  local out = {}
  for _, win in ipairs(L.windows(paw.ui.layout)) do
    if win.view == name then out[#out + 1] = L.within(win, fn, paw.ui.views:get(name)) end
  end
  return out
end

test("window state: two piano rolls on two clips, each with its own cursor", function()
  start()
  local _, clip, other = riff()
  sized(function()
    keys(":e roll://riff<CR>")
    keys(":vs roll://hook<CR>")
  end)
  eq(windows(), "pianoroll pianoroll", "two windows of the roll")
  local clips = each("pianoroll", function(v) return v.clip_id end)
  eq(clips[1] == clip.id and clips[2] == other.id, true, "on two clips")
  local text = screen()
  eq(text:find("riff", 1, true) ~= nil and text:find("hook", 1, true) ~= nil, true, "each drawn with its clip")
  eq(text:find("traceback", 1, true), nil, "neither failed")
  local roll = paw.ui.views:get("pianoroll")
  eq(roll.clip_id, other.id, "the keys act in the new window")
  local left = each("pianoroll", function(v) return v.pitch end)[1]
  keys("kkk")
  local pitches = each("pianoroll", function(v) return v.pitch end)
  eq(pitches[1], left, "the left roll's cursor stays")
  eq(pitches[2], 72 + 3, "the right roll's moved")
  keys("<C-w>h")
  eq(roll.clip_id, clip.id, "Ctrl-w h: the keys act on the left roll's clip")
  eq(paw.ui.location("pianoroll").uri:find("/clip/" .. clip.id, 1, true) ~= nil, true, "its locator")
  local right = L.windows(paw.ui.layout)[2]
  eq(
    paw.ui.location("pianoroll", right).uri:find("/clip/" .. other.id, 1, true) ~= nil,
    true,
    "and the other window's its own"
  )
  -- Each window has an instance of the roll, read without binding it.
  eq(paw.ui.instance("pianoroll").clip_id, clip.id, "paw.ui.instance: the window with the keyboard")
  eq(paw.ui.instance_of(right).clip_id, other.id, "paw.ui.instance_of: the other window's own")
  eq(roll.clip_id, clip.id, "reading an instance binds no window")
  eq(paw.ui.instance("mixer"), nil, "a view without instances has none")
  keys("<C-w>c")
  eq(windows(), "pianoroll", "closing one leaves the other")
  eq(roll.clip_id, other.id, "on its clip")
end)

test("window state: each piano roll edits its own set of clips", function()
  start()
  riff()
  local bass = paw.add_part({ name = "Bass" })
  bass:add_clip({ start = 0, length = 8, name = "line", notes = { { pitch = 40, start = 0, length = 1 } } })
  sized(function()
    keys(":e roll://riff<CR>")
    keys(":vs roll://riff<CR>")
  end)
  screen()
  paw.ui.views:get("pianoroll"):set(40, 0)
  keys("gE")
  local counts = each("pianoroll", function() return #paw.roll_clips.ids() end)
  eq(table.concat(counts, " "), "1 2", "gE edits the bass clip too, in this window only")
end)

test("window state: one score twice, and the notation beside the piano roll of the same clip", function()
  start()
  notation()
  local _, clip = riff()
  sized(function()
    keys(":e notation://riff<CR>")
    keys("<C-w>v")
  end)
  eq(windows(), "notation notation", "Ctrl-w v shows the notation again")
  eq(
    table.concat(each("notation", function(v) return tostring(v.clip_id) end), " "),
    clip.id .. " " .. clip.id,
    "the same clip in both"
  )
  local before = paw.ui.views:get("notation").beat
  keys("l")
  local beats = each("notation", function(v) return v.beat end)
  eq(beats[1], before, "the cursor of the first stays")
  eq(beats[2] ~= before, true, "the cursor of the second moved")
  sized(function() keys(":e roll://riff<CR>") end)
  eq(windows(), "notation pianoroll", "the notation and the roll of the clip side by side")
  local text = screen()
  eq(text:find("traceback", 1, true), nil, "both drawn")
  keys("x")
  paw.flush()
  eq(#clip:notes(), 1, "an edit in the roll")
  eq(screen():find("traceback", 1, true), nil, "and both drawn again")
end)

test("window state: :sp in the roll shows the roll again, on the clip of this window", function()
  start()
  local _, clip = riff()
  sized(function()
    keys(":e roll://riff<CR>")
    keys(":sp<CR>")
  end)
  eq(windows(), "pianoroll pianoroll", "two rolls")
  eq(
    table.concat(each("pianoroll", function(v) return tostring(v.clip_id) end), " "),
    clip.id .. " " .. clip.id,
    "on the same clip"
  )
end)

test("window state: the mixer twice, each window with its own row and scroll", function()
  start()
  for i = 1, 12 do
    paw.add_part({ name = "T" .. i })
  end
  paw.cursor.set_part(paw.parts()[1])
  sized(function()
    keys(":e mixer<CR>")
    keys("<C-w>v")
  end)
  eq(windows(), "mixer mixer", "Ctrl-w v shows the mixer again")
  eq(screen():find("traceback", 1, true), nil, "both drawn")
  local before = each("mixer", function(v) return v.row end)
  eq(before[1], before[2], "the new window starts from the row of the first")
  keys("j")
  local rows = each("mixer", function(v) return v.row end)
  eq(rows[1], before[1], "the left mixer's row stays")
  eq(rows[2] ~= before[2], true, "the right mixer's row moved")
  local mixers = L.windows(paw.ui.layout)
  L.within(mixers[1], function() paw.ui.views:get("mixer").scroll = 0 end)
  L.within(mixers[2], function() paw.ui.views:get("mixer").scroll = 3 end)
  local scrolls = each("mixer", function(v) return v.scroll end)
  eq(scrolls[1] .. " " .. scrolls[2], "0 3", "a scroll for each window")
  keys("<C-w>c")
  eq(windows(), "mixer", "closing one leaves the other")
end)

test("window state: the session view of an extension twice", function()
  start()
  -- The clip launcher's view keeps a state for each window too.
  if not paw.ext.loaded.launcher then
    paw.ext.load("extensions/launcher")
    T.after(function() paw.ext.unload("launcher") end)
  end
  riff()
  sized(function()
    keys(":e session<CR>")
    keys(":sp session<CR>")
  end)
  eq(windows(), "session session", "two session views")
  eq(screen():find("traceback", 1, true), nil, "both drawn")
end)

test("window state: two device panels on two parts", function()
  start()
  local a = paw.add_part({ name = "Lead" })
  local b = paw.add_part({ name = "Bass" })
  a:add_device("delay")
  b:add_device("gain")
  paw.cursor.set_part(a)
  sized(function()
    keys(":e devices<CR>")
    keys(":vs devices://Bass<CR>")
  end)
  eq(windows(), "devices devices", "two device panels")
  local parts = each("devices", function(v) return v:part_id() end)
  eq(parts[1] == a.id and parts[2] == b.id, true, "the left follows the cursor, the right is pinned to Bass")
  local text = screen()
  eq(text:find("Delay", 1, true) ~= nil and text:find("Gain", 1, true) ~= nil, true, "each draws its part's devices")
  eq(text:find("Bass · pinned", 1, true) ~= nil, true, "the pinned one says so")
  eq(text:find("traceback", 1, true), nil, "neither failed")
  -- Keys in the pinned panel act on its part, not on the cursor's.
  keys(":device.add delay<CR>")
  paw.flush()
  eq(#api.part_get(b.id).devices, 2, "a device added in the pinned panel goes on Bass")
  eq(#api.part_get(a.id).devices, 1, "and not on the cursor part")
  eq(paw.cursor.part_id(), b.id, "the part of the keys is the pinned one")
  keys("<C-w>h")
  eq(paw.cursor.part_id(), a.id, "and the cursor's again in the other panel")
  -- The cursor moves: the pinned panel stays, the other follows.
  paw.cursor.set_part(b)
  parts = each("devices", function(v) return v:part_id() end)
  eq(parts[1] .. " " .. parts[2], b.id .. " " .. b.id, "the left follows the cursor to Bass")
  paw.cursor.set_part(a)
  -- \p pins the left panel to the part it shows, and again follows the cursor.
  keys("\\p")
  eq(paw.ui.views:get("devices").pin, a.id, "\\p pins the panel to Lead")
  eq(paw.ui.message ~= nil and tostring(paw.ui.message.text):find("Lead", 1, true) ~= nil, true, "it says what it did")
  paw.cursor.set_part(b)
  eq(each("devices", function(v) return v:part_id() end)[1], a.id, "the pinned panel stays on Lead")
  keys("\\p")
  eq(paw.ui.views:get("devices").pin, nil, "\\p again: it follows the cursor")
  -- A saved layout keeps the pinned part.
  local found = false
  local function walk(node)
    if node.view == "devices" and node.target == b.id then found = true end
    for _, child in ipairs(node.children or {}) do
      walk(child)
    end
  end
  for _, t in ipairs(L.capture().tabs) do
    walk(t.layout)
  end
  eq(found, true, "a saved layout keeps the pinned part")
end)

--- The text a view in a window of its own draws, as one string.
local function painted(name)
  local drawing = paw.canvas.paint(name, 1200, 600, { fresh = true })
  local out = {}
  for _, op in ipairs(drawing and drawing.ops or {}) do
    for _, v in ipairs(op) do
      if type(v) == "string" then out[#out + 1] = v end
    end
  end
  return table.concat(out)
end

test("window state: a piano roll in a window of its own keeps its own clip and cursor", function()
  start()
  local _, clip, other = riff()
  sized(function()
    keys(":e roll://riff<CR>")
    keys(":vs roll://hook<CR>")
  end)
  local roll = paw.ui.views:get("pianoroll")
  keys(":view.window<CR>")
  local own = paw.canvas.open_views.pianoroll
  eq(own ~= nil and own.win ~= nil, true, "the roll of hook is in a window of its own")
  eq(windows(), "pianoroll", "the pane of riff stays")
  eq(painted("pianoroll"):find("hook", 1, true) ~= nil, true, "the window of its own draws hook")
  eq(screen():find("riff", 1, true) ~= nil, true, "the pane draws riff")
  -- Keys typed in the window of its own act on its clip.
  local pitch = roll.pitch
  paw.canvas.key("pianoroll", "k")
  eq(roll.clip_id, other.id, "keys in the window of its own act on hook")
  eq(roll.pitch, pitch + 1, "its cursor moved")
  -- Keys in the main window act on the pane's clip, with its cursor.
  paw.canvas.back("pianoroll")
  keys("<Esc>")
  eq(roll.clip_id, clip.id, "keys in the main window act on riff")
  eq(painted("pianoroll"):find("hook", 1, true) ~= nil, true, "the window of its own still draws hook")
  eq(roll.clip_id, clip.id, "and the pane keeps riff after it draws")
  -- Back into the main window: the pane it left shows what it showed.
  paw.canvas.dock("pianoroll")
  eq(windows(), "pianoroll pianoroll", "back in its pane")
  eq(roll.clip_id, other.id, "on hook")
  eq(roll.pitch, pitch + 1, "with its cursor")
  eq(each("pianoroll", function(v) return v.clip_id end)[1], clip.id, "the other pane keeps riff")
end)

test("window state: the notation in a window of its own keeps its own clip", function()
  start()
  notation()
  local _, clip, other = riff()
  sized(function()
    keys(":e notation://riff<CR>")
    keys(":vs notation://hook<CR>")
  end)
  local score = paw.ui.views:get("notation")
  keys(":view.window<CR>")
  local own = paw.canvas.open_views.notation
  eq(own ~= nil and own.win ~= nil, true, "the notation of hook is in a window of its own")
  eq(windows(), "notation", "the pane of riff stays")
  paw.canvas.paint("notation", 900, 500, { fresh = true })
  eq(score.clip_id, other.id, "the window of its own paints hook")
  paw.layout.settle()
  paw.canvas.back("notation")
  keys("<Esc>")
  eq(score.clip_id, clip.id, "keys in the main window act on riff")
  eq(screen():find("traceback", 1, true), nil, "the pane draws")
  eq(score.clip_id, clip.id, "and keeps riff")
  paw.canvas.close("notation")
end)
