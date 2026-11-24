-- Tests of windows, buffers and tabs in the terminal UI: splits, moving
-- between windows, sizes, tabs, views shown in one window at a time, time
-- bound windows, saved layouts and each seat's own. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api
local K = paw._kernel
local L = paw.layout

local W, H = 160, 48

-- The tabs and windows the suite started with, put back around each test.
local initial = L.capture()

local function reset()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  L.restore(initial)
  paw.ui.focus("arrange")
end

local function start()
  fresh()
  reset()
end

local function screen() return table.concat(api.ui_snapshot(W, H), "\n") end

--- The buffers of empty windows that paw keeps.
local function empties()
  local n = 0
  for _, buf in pairs(L.buffers) do
    if buf.type == "empty" then n = n + 1 end
  end
  return n
end

--- Where each window is on a screen of W by H, by view name.
local function rects()
  local out = {}
  for _, r in ipairs(paw.ui.arrange(W, H)) do
    out[r.name] = r
  end
  return out
end

--- The names of the windows on screen, in order, bars left out.
local function windows()
  local out = {}
  for _, r in ipairs(paw.ui.arrange(W, H)) do
    if r.win then out[#out + 1] = r.name end
  end
  return table.concat(out, " ")
end

local keys = T.keys

local function riff(start_beat)
  local t = paw.add_part({ name = "Keys" })
  local clip = t:add_clip({
    start = start_beat or 0,
    length = 8,
    name = "riff",
    notes = { { pitch = 60, start = 0, length = 1 } },
  })
  paw.cursor.set_part(t)
  return t, clip
end

--- Run `fn` with the screen of the size the tests draw: what a split
--- measures its room against.
local function sized(fn)
  local size = api.ui_size
  api.ui_size = function() return W, H end
  local ok, err = xpcall(fn, debug.traceback)
  api.ui_size = size
  if not ok then error(err, 0) end
end

test("on start the screen is laid out as it always was", function()
  start()
  eq(#paw.ui.tabs, 1, "one tab")
  eq(windows(), "arrange", "the arrange view alone")
  local lines = api.ui_snapshot(W, H)
  eq(lines[1]:find("1 arrange", 1, true), nil, "no tab line with one tab")
  paw.ui.show("mixer")
  paw.ui.show("devices")
  eq(windows(), "arrange devices mixer", "the panels in their places")
  local r = rects()
  eq(r.devices.x > r.arrange.x and r.devices.y == r.arrange.y, true, "the device panel beside the arrange view")
  eq(r.mixer.y > r.arrange.y, true, "the mixer below")
  reset()
end)

test(":vs roll puts the piano roll beside the arrange view, both drawn and both usable", function()
  start()
  local t, clip = riff()
  paw.ui.views:get("pianoroll").clip_id = clip.id
  sized(function() keys(":vs roll<CR>") end)
  eq(paw.ui.focused, "pianoroll", "the new window has the keyboard")
  local r = rects()
  eq(r.pianoroll ~= nil and r.arrange ~= nil, true, "both on screen")
  eq(r.pianoroll.y, r.arrange.y, "side by side")
  eq(r.pianoroll.x > r.arrange.x, true, "the roll on the right")
  eq(math.abs(r.pianoroll.w - r.arrange.w) <= 1, true, "each half the width: " .. r.arrange.w .. " " .. r.pianoroll.w)
  local text = screen()
  eq(text:find("Keys", 1, true) ~= nil, true, "the arrange view draws its part")
  eq(text:find("riff", 1, true) ~= nil, true, "the roll draws its clip")
  eq(text:find("traceback", 1, true), nil, "neither failed")
  local roll = paw.ui.views:get("pianoroll")
  local pitch = roll.pitch
  keys("k")
  eq(roll.pitch, pitch + 1, "keys in the roll move its cursor")
  keys("<C-w>h")
  eq(paw.ui.focused, "arrange", "Ctrl-w h goes to the arrange view")
  paw.add_part({ name = "Bass" })
  paw.cursor.set_part(t)
  keys("j")
  eq(paw.cursor.part().name, "Bass", "and keys there move its cursor")
  keys("<C-w>l")
  eq(paw.ui.focused, "pianoroll", "Ctrl-w l back to the roll")
  -- Opening a clip shows it in the window the roll is in.
  paw.ui.focus("arrange")
  roll:edit(clip)
  eq(windows(), "arrange pianoroll", "the roll stays where it was put")
  reset()
end)

test("Enter on a clip opens the piano roll below the arrange view, as before", function()
  start()
  local _, clip = riff()
  paw.ui.views:get("pianoroll"):edit(clip)
  local r = rects()
  eq(r.pianoroll.y > r.arrange.y and r.pianoroll.x == r.arrange.x, true, "below")
  eq(paw.ui.focused, "pianoroll", "with the keyboard")
  keys("<C-w>c")
  eq(windows(), "arrange", "Ctrl-w c closes it")
  eq(paw.ui.focused, "arrange", "and the keyboard goes back")
  paw.ui.views:get("pianoroll"):edit(clip)
  eq(windows(), "arrange pianoroll", "it comes back where it was")
  reset()
end)

test(
  "a view without a state for each window is in one window at a time: showing it in another moves it there",
  function()
    start()
    riff()
    -- A view of one state, as an extension may make.
    if not paw.ui.views:get("single") then
      paw.ui.view("single", { render = function(_, buf) buf:text(0, 0, "single") end })
    end
    sized(function()
      keys(":vs single<CR>")
      keys("<C-w>h")
      keys(":sp single<CR>")
    end)
    eq(windows(), "arrange single", "one window of it, now below the arrange view")
    local r = rects()
    eq(r.single.x == r.arrange.x and r.single.y > r.arrange.y, true, "below it")
    eq(
      paw.ui.message and paw.ui.message.text:find("moved", 1, true) ~= nil,
      true,
      "with a message: " .. tostring(paw.ui.message and paw.ui.message.text)
    )
    keys(":e roll<CR>")
    eq(windows(), "arrange pianoroll", ":e shows another buffer in the window")
    reset()
  end
)

test("splits, empty windows, closing, only, and :q closing a window before it quits", function()
  start()
  local quits = 0
  local quit = api.quit
  api.quit = function() quits = quits + 1 end
  local ok, err = pcall(function()
    sized(function()
      keys(":vnew<CR>")
      eq(windows(), "arrange empty", ":vnew opens an empty window")
      eq(screen():find("Show something here", 1, true) ~= nil, true, "the start page, which says what to do")
      keys("<C-w>s")
      eq(windows(), "arrange empty empty", "Ctrl-w s splits it")
      keys("<C-w>o")
      eq(windows(), "empty", "Ctrl-w o keeps only it")
      keys(":e arrange<CR>")
      eq(windows(), "arrange", "the arrange view shown in it")
      keys(":vs mixer<CR>")
    end)
    keys(":q<CR>")
    eq(windows(), "arrange", ":q closes the window")
    eq(quits, 0, "and does not quit")
    keys(":close<CR>")
    eq(windows(), "arrange", "the last window does not close")
    keys(":q<CR>")
    eq(quits, 1, "and :q in it quits")
  end)
  api.quit = quit
  if not ok then error(err, 0) end
  eq(empties(), 0, "empty buffers are forgotten with their windows")
  reset()
end)

test("Ctrl-w moves between windows, moves them, exchanges and rotates them", function()
  start()
  riff()
  sized(function()
    keys(":vs roll<CR>")
    keys(":sp mixer<CR>")
  end)
  eq(windows(), "arrange pianoroll mixer", "three windows")
  local r = rects()
  eq(r.mixer.x == r.pianoroll.x and r.mixer.y > r.pianoroll.y, true, "the mixer below the roll")
  keys("<C-w>k")
  eq(paw.ui.focused, "pianoroll", "Ctrl-w k goes up")
  keys("<C-w>j")
  eq(paw.ui.focused, "mixer", "Ctrl-w j goes down")
  keys("<C-w>h")
  eq(paw.ui.focused, "arrange", "Ctrl-w h goes left")
  keys("<C-w>p")
  eq(paw.ui.focused, "mixer", "Ctrl-w p goes back to the window before")
  keys("<C-w>w")
  eq(paw.ui.focused, "arrange", "Ctrl-w w goes round")
  keys("<C-w>l")
  keys("<C-w>x")
  eq(windows(), "arrange mixer pianoroll", "Ctrl-w x exchanges the roll and the mixer")
  eq(paw.ui.focused, "pianoroll", "the keyboard stays with the roll")
  keys("<C-w>r")
  eq(windows(), "arrange pianoroll mixer", "Ctrl-w r rotates them")
  keys("<C-w>J")
  r = rects()
  eq(r.pianoroll.x, 0, "Ctrl-w J: the roll along the bottom")
  eq(r.pianoroll.w, W, "the whole width")
  eq(r.pianoroll.y > r.arrange.y and r.pianoroll.y > r.mixer.y, true, "below the others")
  keys("<C-w>K")
  r = rects()
  eq(r.pianoroll.y, 0, "Ctrl-w K: along the top")
  keys("<C-w>L")
  r = rects()
  eq(r.pianoroll.x + r.pianoroll.w, W, "Ctrl-w L: along the right")
  eq(r.pianoroll.h, H - 2, "the whole height")
  keys("<C-w>H")
  r = rects()
  eq(r.pianoroll.x, 0, "Ctrl-w H: along the left")
  reset()
end)

test("windows are resized by keys, by :resize and by dragging their border", function()
  start()
  riff()
  sized(function()
    keys(":vs roll<CR>")
    keys(":vertical resize 50<CR>")
    eq(rects().pianoroll.w, 50, ":vertical resize sets the width")
    keys(":vertical resize -10<CR>")
    eq(rects().pianoroll.w, 40, "and changes it")
    keys("4<C-w>>")
    eq(rects().pianoroll.w, 48, "Ctrl-w > with a count, two columns a step")
    keys("<C-w>=")
    local r = rects()
    eq(math.abs(r.pianoroll.w - r.arrange.w) <= 1, true, "Ctrl-w = makes them equal")
    keys(":sp mixer<CR>")
    keys(":resize 20<CR>")
    eq(paw.opt.mixer_height, 20, "a panel's height is its option")
    keys(":resize +2<CR>")
    eq(paw.opt.mixer_height, 22, "and grows")
    paw.opt.mixer_height = 12
    -- The rule between the arrange view and the roll, dragged.
    screen()
    local border = rects().pianoroll.x
    paw.ui.mouse({ kind = "down", button = "left", x = border, y = 10 })
    paw.ui.mouse({ kind = "drag", button = "left", x = 100, y = 10 })
    paw.ui.mouse({ kind = "up", button = "left", x = 100, y = 10 })
    r = rects()
    eq(r.arrange.w, 100, "dragging the border resizes")
    eq(r.pianoroll.x, 100, "both sides")
    -- A click in a window gives it the keyboard.
    screen()
    paw.ui.mouse({ kind = "down", button = "left", x = 5, y = 5 })
    paw.ui.mouse({ kind = "up", button = "left", x = 5, y = 5 })
    eq(paw.ui.focused, "arrange", "a click focuses the window")
  end)
  reset()
end)

test("Ctrl-w + resizes a window only, never the parts", function()
  start()
  keys("<C-w>+")
  eq(L.current().vzoom, nil, "alone: no taller parts (that is Ctrl-=)")
  sized(function()
    keys(":sp mixer<CR>")
    keys("<C-w>k")
    local before = rects().arrange.h
    keys("<C-w>+")
    eq(rects().arrange.h, before + 1, "the window")
  end)
  reset()
end)

test("Ctrl-w _ gives a window the tab and puts the others back", function()
  start()
  riff()
  sized(function() keys(":vs roll<CR>") end)
  keys("<C-w>_")
  eq(windows(), "pianoroll", "the roll alone")
  keys("<C-w>_")
  eq(windows(), "arrange pianoroll", "and back")
  eq(paw.ui.focused, "pianoroll", "with the keyboard where it was")
  reset()
end)

test("tabs: :tabnew, gt and gT, a tab line, Ctrl-w T, :tabclose", function()
  start()
  riff()
  keys(":tabnew mixer<CR>")
  eq(#paw.ui.tabs, 2, "two tabs")
  eq(paw.ui.tab, 2, "in the new one")
  eq(windows(), "mixer", "showing the mixer")
  eq(paw.ui.focused, "mixer", "with the keyboard")
  local lines = api.ui_snapshot(W, H)
  eq(
    lines[1]:find("1 arrange", 1, true) ~= nil and lines[1]:find("2 mixer", 1, true) ~= nil,
    true,
    "a tab line: " .. lines[1]
  )
  keys("gt")
  eq(paw.ui.tab, 1, "gt to the next tab, round the end")
  eq(paw.ui.focused, "arrange", "where the keyboard was")
  keys("gT")
  eq(paw.ui.tab, 2, "gT back")
  keys("gt")
  paw.ui.toggle("mixer")
  eq(windows(), "arrange mixer", "Space mm shows the mixer here")
  keys("gt")
  eq(windows(), "mixer", "and the other tab keeps its own: the mixer shows in any number of windows")
  screen()
  paw.ui.mouse({ kind = "down", button = "left", x = 1, y = 0 })
  eq(paw.ui.tab, 1, "a click on a tab goes to it")
  sized(function()
    keys("<C-w>j")
    keys("<C-w>T")
  end)
  eq(paw.ui.tab, 2, "Ctrl-w T: the mixer in a tab of its own, after this one")
  eq(#paw.ui.tabs, 3, "three tabs")
  eq(windows(), "mixer", "alone there")
  keys(":tabclose<CR>")
  keys(":tabclose<CR>")
  eq(#paw.ui.tabs, 1, ":tabclose")
  keys(":tabnew Mix<CR>")
  eq(paw.layout.tab_title(paw.ui.tabs[2]), "Mix", "a tab named")
  eq(windows(), "empty", "with an empty window")
  keys(":q<CR>")
  eq(#paw.ui.tabs, 1, ":q in a tab's last window closes the tab")
  reset()
end)

test("buffers are listed, named and gone through", function()
  start()
  riff()
  local names = {}
  for _, buf in ipairs(paw.buf.list()) do
    names[#names + 1] = buf.name
  end
  local list = " " .. table.concat(names, " ") .. " "
  eq(
    list:find(" arrange ", 1, true) ~= nil
      and list:find(" roll ", 1, true) ~= nil
      and list:find(" mixer ", 1, true) ~= nil,
    true,
    "the views' buffers: " .. list
  )
  local done = {}
  for _, c in ipairs(paw.commands.complete("vs ro")) do
    done[#done + 1] = c.text
  end
  eq(done[1], "vs roll", "names complete")
  keys(":b mixer<CR>")
  eq(windows(), "mixer", ":b shows a buffer in the window")
  keys(":b arrange<CR>")
  local before = windows()
  keys(":bn<CR>")
  eq(windows() ~= before, true, ":bn shows the next")
  keys(":bp<CR>")
  eq(windows(), before, ":bp the one before")
  keys(":ls<CR>")
  eq(paw.ui.float and paw.ui.float.title, "Buffers", ":ls lists them")
  reset()
end)

test("a buffer type of its own has a buffer for each target and any number of windows", function()
  start()
  local drawn = {}
  paw.buftype("probe", {
    create = function(target) return { label = "probe " .. tostring(target) } end,
    render = function(win, canvas, ctx)
      win.state.draws = (win.state.draws or 0) + 1
      drawn[#drawn + 1] = ctx.buf.state.label
      canvas:text(0, 0, ctx.buf.state.label)
    end,
    on_key = function(win, key) win.state.key = key end,
  })
  sized(function()
    keys(":vs probe://a<CR>")
    keys(":sp probe://b<CR>")
    keys(":sp probe://a<CR>")
  end)
  eq(windows(), "arrange probe probe probe", "three windows of the type")
  local text = screen()
  eq(text:find("probe a", 1, true) ~= nil and text:find("probe b", 1, true) ~= nil, true, "each drawing its buffer")
  local a = 0
  for _, buf in pairs(L.buffers) do
    if buf.type == "probe" and buf.target == "a" then a = a + 1 end
  end
  eq(a, 1, "one buffer for a target, in two windows")
  keys("<F9>")
  eq(L.current().state.key, "<F9>", "keys with no mapping go to the type, with the window")
  reset()
  paw.ui.views:remove("probe")
  L.types:remove("probe")
  for id, buf in pairs(L.buffers) do
    if buf.type == "probe" then L.buffers[id] = nil end
  end
end)

test("time bound windows scroll and zoom together, led by the one with the keyboard", function()
  start()
  local _, clip = riff(8)
  local roll, arrange = paw.ui.views:get("pianoroll"), paw.ui.views:get("arrange")
  roll.clip_id = clip.id
  local zoom, note_zoom = paw.opt.zoom, paw.opt.note_zoom
  sized(function() keys(":vs roll<CR>") end)
  keys(":setlocal timebind<CR>")
  keys("<C-w>h")
  keys(":setlocal timebind<CR>")
  eq(paw.win.option(nil, "timebind"), true, "a window option")
  screen()
  arrange.scroll = 16
  screen()
  eq(roll.scroll, 8, "the roll shows from where the arrange view does, its clip starting at 8")
  eq(paw.opt.note_zoom, paw.opt.zoom, "at its zoom")
  keys("<C-w>l")
  screen()
  roll.beat, roll.scroll = 6, 4
  screen()
  eq(arrange.scroll, 12, "led by the roll, the arrange view follows")
  keys(":setlocal notimebind<CR>")
  roll.scroll = 0
  screen()
  eq(arrange.scroll, 12, "unbound, it stays")
  paw.opt.zoom, paw.opt.note_zoom = zoom, note_zoom
  reset()
end)

test("layouts are saved and put back, and a configuration names its own", function()
  start()
  riff()
  sized(function() keys(":vs roll<CR>") end)
  keys(":setlocal timebind<CR>")
  keys(":layout save probe_split<CR>")
  reset()
  eq(windows(), "arrange", "back to the start")
  keys(":layout probe_split<CR>")
  eq(windows(), "arrange pianoroll", "the saved layout")
  eq(paw.win.option(nil, "timebind"), true, "with its window options")
  paw.layouts.probe_tabs = {
    { name = "Edit", layout = { dir = "h", "arrange", "roll" } },
    { name = "Mix", layout = "mixer" },
  }
  keys(":layout probe_tabs<CR>")
  eq(#paw.ui.tabs, 2, "a configuration's layout: two tabs")
  eq(windows(), "arrange pianoroll", "the first as it says")
  eq(paw.layout.tab_title(paw.ui.tabs[2]), "Mix", "the second named")
  local found = {}
  for _, name in ipairs(L.layout_names()) do
    found[name] = true
  end
  eq(found.probe_split and found.probe_tabs, true, "both listed")
  os.remove(api.env().state_dir .. "/layouts/probe_split.json")
  paw.layouts.probe_tabs = nil
  paw.ui.toggle("mixer")
  eq(windows(), "arrange mixer pianoroll", "a panel not in a layout docks below the window with the keyboard")
  reset()
end)

test("a layout put back forgets the empty windows it closes", function()
  start()
  paw.layouts.probe_plain = { { layout = "arrange" } }
  T.after(function()
    paw.layouts.probe_plain = nil
    reset()
  end)
  local function empties()
    local n = 0
    for _, buf in pairs(L.buffers) do
      if buf.type == "empty" then n = n + 1 end
    end
    return n
  end
  local before = empties()
  keys(":vnew<CR>")
  eq(empties(), before + 1, ":vnew makes an empty buffer")
  keys(":layout probe_plain<CR>")
  eq(windows(), "arrange", "the layout")
  eq(empties(), before, "the empty window's buffer goes with it")
end)

test("every seat has tabs and windows of its own", function()
  start()
  riff()
  K.seat_open(7, "terminal")
  local ok, err = pcall(function()
    K.seat(7)
    sized(function() paw.cmd("vsplit", { "roll" }) end)
    local there = windows()
    K.seat(0)
    eq(there, "arrange pianoroll", "a split in the terminal's seat")
    eq(windows(), "arrange", "not in the instance's")
    K.seat(7)
    paw.cmd("tabnew", { "Mix" })
    local tabs = #paw.ui.tabs
    K.seat(0)
    eq(tabs, 2, "a tab there")
    eq(#paw.ui.tabs, 1, "not here")
  end)
  K.seat(0)
  local before = empties()
  K.seat_close(7)
  if not ok then error(err, 0) end
  eq(before > 0, true, "the seat's new tab has an empty window")
  eq(empties(), 0, "which is forgotten with the seat")
  reset()
end)

test("every view still opens: by its keys, and in a window of its own", function()
  start()
  local _, clip = riff()
  paw.cursor.set_beat(0)
  keys("<leader>mm")
  eq(paw.ui.visible("mixer"), true, "Space mm the mixer")
  keys("<leader>dd")
  eq(paw.ui.visible("devices"), true, "Space dd the device panel")
  keys("<leader>vp")
  eq(paw.ui.visible("pianoroll"), true, "Space vp the piano roll")
  reset()
  keys("?")
  eq(paw.ui.float ~= nil, true, "? the keys, floating")
  reset()
  -- An extension's painted views are views too.
  paw.cmd("ext.load", { "undotree" })
  paw.ui.views:get("pianoroll").clip_id = clip.id
  local failed = {}
  for name, view in pairs(paw.ui.views:entries()) do
    if view.focusable ~= false and not view.buftype then
      sized(function()
        keys(":vnew<CR>")
        keys(":e " .. (L.names[name] or view.bufname or name) .. "<CR>")
      end)
      local text = screen()
      if not paw.ui.visible(name) then
        failed[#failed + 1] = name .. " (not shown)"
      elseif text:find("traceback", 1, true) then
        failed[#failed + 1] = name .. " (failed to draw)"
      end
      reset()
    end
  end
  table.sort(failed)
  eq(table.concat(failed, ", "), "", "every view shows in a window")
end)
