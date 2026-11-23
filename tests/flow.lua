-- Working from the keyboard: the keys picker, command-line completion, exact
-- values, sizes, undo labels, automation lanes as rows, and limits on
-- runaway Lua.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api
local pick = paw.pick

local function screen(w, h) return table.concat(api.ui_snapshot(w or 100, h or 30), "\n") end

local function has(text, part, what)
  if not text:find(part, 1, true) then error(string.format("%s: %q is not in\n%s", what or "text", part, text), 2) end
end

local function lacks(text, part, what)
  if text:find(part, 1, true) then
    error(string.format("%s: %q should not be in\n%s", what or "text", part, text), 2)
  end
end

local function start()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
end

-- The keys picker -------------------------------------------------------------

test("keys are written as a person writes them", function()
  local human = paw.keymap.human
  eq(human("<A-h>"), "Alt-h", "Alt")
  eq(human("<leader>at"), "Space at", "the leader")
  eq(human("<C-w>o"), "Ctrl-w o", "a key after a chord stands apart")
  eq(human("<C-w><lt>"), "Ctrl-w <", "<lt> is <")
  eq(human("<CR>"), "Enter", "Enter")
  eq(human("<S-Tab>"), "Shift-Tab", "Shift")
  eq(human("gg"), "gg", "plain keys run together")
  eq(human("<leader><Space>"), "Space Space", "play")
end)

test("? opens a picker of the keys for the focused view, titled with it", function()
  start()
  paw.keymap.feed("?")
  local state = pick.state()
  eq(state and state.title, "Keys · arrange", "the title names the view")
  local text = table.concat(state.matches, "\n")
  has(text, "Alt-h", "a key of the arrange view, humanised")
  has(text, "Ctrl-w o", "a global key")
  has(text, "arrange", "a tag says where a key works")
  has(text, "global", "and for global ones")
  has(text, "operator", "operators are marked")
  paw.keymap.feed("<Esc>")
end)

test("typing in the keys picker filters, and Enter runs the key", function()
  start()
  local ran
  paw.keymap.set("gQ", function() ran = true end, { view = "arrange", desc = "zz flow mapping" })
  paw.keymap.feed("?zz flow")
  eq(#pick.state().matches, 1, "one match")
  paw.keymap.feed("<CR>")
  eq(ran, true, "Enter ran the mapping")
  eq(pick.state(), nil, "and closed the picker")
  paw.keymap.del("gQ", { view = "arrange" })
end)

test("the keys picker ranks a match on the key above one in a description", function()
  start()
  paw.keymap.feed("?gg")
  local first = pick.state().matches[1]
  eq(first:match("^gg ") ~= nil, true, "gg first: " .. first)
  paw.keymap.feed("<Esc>")
end)

test(":help all lists every key in one page", function()
  start()
  paw.cmd("help", { "all" })
  eq(paw.ui.float and paw.ui.float.name, "help", "the long list")
  local keys = {}
  for _, line in ipairs(paw.ui.views:get("help").lines) do
    keys[#keys + 1] = line.key or ""
  end
  has(table.concat(keys, "\n"), "Ctrl-w o", "with keys humanised")
  paw.ui.close()
end)

test("the commands picker shows each command's key and ranks names first", function()
  start()
  paw.pick("commands")
  local lines = pick.state().matches
  local undo
  for _, line in ipairs(lines) do
    if line:match("^undo ") then undo = line end
  end
  paw.keymap.feed("<Esc>")
  eq(undo ~= nil and undo:find(" u ", 1, true) ~= nil, true, "undo shows its key u: " .. tostring(undo))
  paw.command("zz_aaa", function() end, { desc = "mentions mute in passing" })
  paw.pick("commands", { query = "mute" })
  local first = pick.state().matches[1]
  paw.keymap.feed("<Esc>")
  eq(first:match("^%S*mute") ~= nil, true, "a command named mute first: " .. first)
end)

-- Command-line completion -----------------------------------------------------

local function prompt() return require("paw.views.cmdline").state() end

test("typing on the command line lists the commands it could be, with what they do", function()
  start()
  paw.keymap.feed(":track.mu")
  local state = prompt()
  eq(state.matches and #state.matches > 0, true, "candidates while typing")
  eq(state.matches[1].label, "track.mute", "the command that starts with it")
  eq(state.match, 0, "none chosen yet")
  local text = screen(100, 30)
  has(text, "Toggle mute", "the description is shown")
  paw.keymap.feed("<Tab>")
  eq(prompt().before, "track.mute", "Tab puts the first one in the line")
  has(screen(100, 30), "▶", "and marks it")
  paw.keymap.feed("<Esc>")
  eq(prompt(), nil, "Esc closes the prompt")
  lacks(screen(100, 30), "Toggle mute", "and the list with it")
end)

test("the list shows at most ten, and Tab and Shift-Tab move through them all", function()
  start()
  paw.keymap.feed(":track.")
  local n = #prompt().matches
  eq(n > 10, true, "more than ten track commands")
  local rows = 0
  for line in screen(100, 30):gmatch("[^\n]+") do
    if line:find("Toggle mute", 1, true) or line:find("Toggle solo", 1, true) or line:find("track%.") then
      rows = rows + 1
    end
  end
  eq(rows <= 11, true, "no more than ten rows of candidates and the prompt: " .. rows)
  paw.keymap.feed("<Tab><Tab><S-Tab>")
  eq(prompt().match, 1, "Tab twice, Shift-Tab once")
  paw.keymap.feed("<Esc>")
end)

test("arguments complete as the command says: tracks by name, quoted when they have a space", function()
  start()
  paw.add_track({ name = "Lead Guitar" })
  paw.add_track({ name = "Reverb" })
  local t = paw.add_track({ name = "Vox" })
  paw.cursor.set_track(t)
  local list = paw.commands.complete("send Rev")
  eq(list[1] and list[1].text, "send Reverb", "a track for send")
  list = paw.commands.complete("send Lead")
  eq(list[1] and list[1].text, 'send "Lead Guitar"', "quoted")
  paw.command("zz_raw", function() end, { raw = true, complete = "tracks" })
  list = paw.commands.complete("zz_raw Lead")
  eq(list[1] and list[1].text, "zz_raw Lead Guitar", "a command that takes its text whole needs no quotes")
  eq(#paw.commands.complete("send Reverb "), 0, "the level after the track is not completed")
  paw.keymap.feed(":send Rev<Tab><CR>")
  eq(#t:get().sends, 1, "Tab then Enter runs it")
end)

test("devices, options, views and files complete", function()
  start()
  local function first(line)
    local list = paw.commands.complete(line)
    return list[1] and list[1].text
  end
  eq(first("device.add dela"), "device.add delay", "a device kind")
  eq(first("set zoo"), "set zoom", "an option")
  eq(first("view.toggle mix"), "view.toggle mixer", "a view")
  T.write_file(T.scratch .. "/flowfile.wav", "")
  eq(first("open " .. T.scratch .. "/flowf"), "open " .. T.scratch .. "/flowfile.wav", "a file")
  local dirs = paw.commands.complete("import " .. T.scratch:match("^(.*/)"))
  local found
  for _, c in ipairs(dirs) do
    if c.label:match("/$") then found = true end
  end
  eq(found, true, "directories end in /")
end)

test(":set shows, sets and flips options", function()
  start()
  local zoom = paw.opt.zoom
  paw.keymap.feed(":set zoom 7<CR>")
  eq(paw.opt.zoom, 7, "set name value")
  paw.cmd("set", { zoom = 3 })
  eq(paw.opt.zoom, 3, "set name=value")
  local follow = paw.opt.follow
  paw.keymap.feed(":set follow!<CR>")
  eq(paw.opt.follow, not follow, "! flips")
  paw.opt.follow, paw.opt.zoom = follow, zoom
end)

-- Exact values ----------------------------------------------------------------

test("grv, grp and grt take a typed value, or a step from the one there is", function()
  start()
  local t = paw.add_track({ name = "Vox", volume = -8 })
  paw.cursor.set_track(t)
  T.keys("grv-6.5<CR>")
  eq(t.volume, -6.5, "-6.5 is -6.5 dB, as a musician reads it")
  T.keys("grv=-6<CR>")
  eq(t.volume, -6, "=-6 sets it too")
  T.keys("grv+=2<CR>")
  eq(t.volume, -4, "+=2 steps up")
  T.keys("grv-=3<CR>")
  eq(t.volume, -7, "-=3 steps down")
  T.keys("grv+2<CR>")
  eq(t.volume, 2, "+2 is +2 dB")
  T.keys("grv3 dB<CR>")
  eq(t.volume, 3, "a plain number, with its unit")
  T.keys("grpL30<CR>")
  T.near(t.pan, -0.3, 1e-9, "L30 is 30% left")
  T.keys("grp+=50<CR>")
  T.near(t.pan, 0.2, 1e-9, "+=50 steps right")
  T.keys("grp-20<CR>")
  T.near(t.pan, -0.2, 1e-9, "-20 is 20% left")
  T.keys("grpC<CR>")
  eq(t.pan, 0, "C is the centre")
  local tempo = paw.project.tempo
  T.keys("grt140<CR>")
  eq(paw.project.tempo, 140, "the tempo")
  T.keys("grt-=10<CR>")
  eq(paw.project.tempo, 130, "stepped")
  paw.project.tempo = tempo
  T.keys("grvloud<CR>")
  eq(t.volume, 3, "text that is not a value changes nothing")
end)

test("in the mixer grv sets the selected strip's volume", function()
  start()
  local a = paw.add_track({ name = "A" })
  local b = paw.add_track({ name = "B" })
  paw.cursor.set_track(b)
  paw.ui.focus("mixer")
  T.keys("grv=-12<CR>")
  eq(b.volume, -12, "the strip under the cursor")
  eq(a.volume, 0, "not another")
  paw.ui.hide("mixer")
  paw.ui.focus("arrange")
end)

test("c and = in the device panel ask for the parameter's value in its unit", function()
  start()
  local t = paw.add_track({ name = "S" })
  t:add_device("synth")
  paw.cursor.set_track(t)
  paw.ui.focus("devices")
  local panel = paw.ui.views:get("devices")
  local cutoff
  for i, row in ipairs(panel:rows()) do
    if row.param and row.param.key == "cutoff" then
      panel.row, cutoff = i, row
    end
  end
  T.keys("c800<CR>")
  eq(api.device_get(cutoff.device.id).params.cutoff, 800, "cutoff 800 Hz")
  T.keys("c+=200<CR>")
  eq(api.device_get(cutoff.device.id).params.cutoff, 1000, "+=200 steps")
  for i, row in ipairs(panel:rows()) do
    if row.param and #row.param.choices > 0 then
      panel.row, cutoff = i, row
    end
  end
  if cutoff.param.choices[2] then
    T.keys("c" .. cutoff.param.choices[2] .. "<CR>")
    eq(api.device_get(cutoff.device.id).params[cutoff.param.key], 1, "a choice by its name")
  end
  paw.ui.hide("devices")
  paw.ui.focus("arrange")
end)

-- Sizes -----------------------------------------------------------------------

test("Ctrl-w < and > change the side panel's width or the header width; sizes are options", function()
  start()
  local hw, dw = paw.opt.header_width, paw.opt.devices_width
  paw.opt.header_width = 24
  paw.keymap.feed("<C-w>>")
  eq(paw.opt.header_width, 26, "the header in the arrange view")
  paw.ui.focus("devices")
  paw.keymap.feed("<C-w><lt>")
  eq(paw.opt.devices_width, dw - 2, "the device panel")
  local rects = paw.ui.arrange(120, 30)
  local width
  for _, r in ipairs(rects) do
    if r.name == "devices" then width = r.w end
  end
  eq(width, dw - 2, "and it is drawn so")
  paw.opt.devices_width = 50
  for _, r in ipairs(paw.ui.arrange(120, 30)) do
    if r.name == "devices" then width = r.w end
  end
  eq(width, 50, "setting the option sets the size")
  paw.ui.focus("mixer")
  paw.keymap.feed("<C-w>+")
  eq(paw.opt.mixer_height, 13, "a panel below grows taller")
  paw.opt.header_width, paw.opt.devices_width, paw.opt.mixer_height = hw, dw, 12
  paw.ui.hide("mixer")
  paw.ui.hide("devices")
  paw.ui.focus("arrange")
end)

test("Ctrl-w _ maximises the focused panel and puts the others back", function()
  start()
  paw.ui.show("devices")
  paw.ui.show("mixer")
  paw.ui.focus("devices")
  paw.keymap.feed("<C-w>_")
  local names = {}
  for _, r in ipairs(paw.ui.arrange(120, 30)) do
    names[#names + 1] = r.name .. ":" .. r.w
  end
  eq(table.concat(names, " "), "devices:120 status:120 cmdline:120", "only the panel, the whole width")
  paw.keymap.feed("<C-w>_")
  names = {}
  for _, r in ipairs(paw.ui.arrange(120, 30)) do
    names[#names + 1] = r.name
  end
  eq(table.concat(names, " "), "arrange devices mixer status cmdline", "back as it was")
  eq(paw.ui.focused, "devices", "with the panel focused")
  paw.ui.hide("mixer")
  paw.ui.hide("devices")
  paw.ui.focus("arrange")
end)

-- Undo steps with names ---------------------------------------------------------

local function current_label()
  local current = api.undo_current()
  for _, s in ipairs(api.undo_tree().states) do
    if s.id == current then return s.label end
  end
end

test("an undo step is named by the key or command that made it", function()
  start()
  local t = paw.add_track({ name = "T" })
  t:add_clip({ start = 0, length = 4, name = "c" })
  paw.cursor.set_track(t)
  paw.cursor.set_beat(0)
  api.undo_checkpoint()
  paw._kernel.key("x")
  api.undo_checkpoint()
  eq(current_label(), "Delete the clip", "the key's description")
  paw.undo()
  paw._kernel.key("d")
  paw._kernel.key("w")
  api.undo_checkpoint()
  eq(current_label(), "Delete", "an operator names the step, not its motion")
  paw.cmd("track.volume", { -3 })
  api.undo_checkpoint()
  eq(current_label(), "Set the volume in dB", "a command's description, without examples")
  -- Each key is a turn of its own, as at the keyboard.
  for _, key in ipairs({ "g", "r", "v", "-", "1", "<CR>" }) do
    paw._kernel.key(key)
    api.undo_checkpoint()
  end
  eq(current_label(), "Set T volume", "a value typed at a prompt")
end)

test("a choice in a picker names the step by what it changed", function()
  start()
  local t = paw.add_track({ name = "Lead" })
  paw.cursor.set_track(t)
  api.undo_checkpoint()
  local function typed(list)
    for _, key in ipairs(list) do
      paw.keymap.feed(key)
      paw.flush()
      api.undo_checkpoint()
    end
  end
  typed({ "a", "synth", "<CR>" })
  eq(#t:devices(), 1, "a synth<CR> adds the synth")
  eq(current_label(), "add Synth to Lead", "the device and the track")
  typed({ "grC", "teal", "<CR>" })
  eq(current_label(), "color of Lead", "grC names the track")
end)

test("u and Ctrl-r say what they undid and redid", function()
  start()
  local t = paw.add_track({ name = "T" })
  paw.cursor.set_track(t)
  api.undo_checkpoint()
  paw._kernel.key("M")
  api.undo_checkpoint()
  paw._kernel.key("u")
  eq(paw.ui.message and paw.ui.message.text, "undid Mute the track", "u")
  eq(t.mute, false, "undone")
  paw._kernel.key("<C-r>")
  eq(paw.ui.message and paw.ui.message.text, "redid Mute the track", "Ctrl-r")
end)

-- After an error ----------------------------------------------------------------

test("after an error the key line says how to read it, until it is read", function()
  start()
  paw.notify("something broke\nwith details", "error")
  local last = screen(120, 30):match("([^\n]*)$")
  has(last, "something broke", "the error itself")
  has(last, "Space fl or :messages shows it all", "and how to see it whole")
  paw.ui.message = nil
  last = screen(120, 30):match("([^\n]*)$")
  has(last, "Space fl last error", "once it has gone, the key line still says so")
  paw.cmd("messages")
  local text = screen(120, 30)
  paw.ui.close()
  has(text, "with details", ":messages shows the whole of it, newest at the bottom")
  paw.ui.message = nil
  last = screen(120, 30):match("([^\n]*)$")
  lacks(last, "last error", "read, it is no longer mentioned")
end)

-- Automation lanes as rows ------------------------------------------------------

local function lane_setup()
  start()
  paw.lanes.open(1, false)
  for _, id in ipairs(api.track_list()) do
    paw.lanes.open(id, false)
  end
  local t = paw.add_track({ name = "Lead", volume = -6 })
  t:add_device("synth")
  local other = paw.add_track({ name = "Other" })
  paw.cursor.set_track(t)
  paw.cursor.set_beat(0)
  paw.opt.grid = 1
  return t, other
end

local function points(lane)
  local out = {}
  for i, p in ipairs(api.lane_points(lane)) do
    out[i] = string.format("%g:%g", p[1], p[2])
  end
  return table.concat(out, " ")
end

test("Space al chooses what to automate and shows its lane as a row under the track", function()
  local t = lane_setup()
  paw.keymap.feed("<leader>al")
  local state = pick.state()
  eq(state and state.title, "Automate on Lead", "the lane picker")
  local text = table.concat(state.matches, "\n")
  has(text, "Volume", "volume")
  has(text, "Pan", "pan")
  has(text, "Synth › cutoff", "a device's parameter")
  paw.keymap.feed("cutoff<CR>")
  local lane = paw.cursor.lane_id()
  eq(lane ~= nil, true, "the cursor is on the new lane's row")
  eq(api.lane_get(lane).param, "cutoff", "a cutoff lane")
  eq(paw.lanes.is_open(t), true, "the track's lanes are open")
  local rows = paw.groups.rows({ lanes = true })
  eq(#rows, 3, "two tracks and one lane row")
  eq(rows[2].lane, lane, "the lane is a row under its track")
  eq(paw.cursor.line(), 2, "the cursor's row among them")
  eq(paw.cursor.row(), 1, "and its track's row among tracks")
  local text2 = screen(120, 30)
  has(text2, "↳ Synth › cutoff", "the lane header names the parameter")
  has(text2, "read", "and says the lane is read")
end)

test("on a lane row A adds a point at the curve's value, + - c change it, x removes it", function()
  local t = lane_setup()
  local lane = t:automate("volume")
  paw.lanes.open(t)
  paw.cursor.set_track(t.id, lane.id)
  T.keys("A")
  eq(points(lane.id), "0:-6", "the track's volume, with no points yet")
  T.keys("4lA")
  eq(points(lane.id), "0:-6 4:-6", "the curve's value there")
  T.keys("+")
  eq(points(lane.id), "0:-6 4:-5", "+ raises the point under the cursor a dB")
  T.keys("3-")
  eq(points(lane.id), "0:-6 4:-8", "a count")
  T.keys("c=-20<CR>")
  eq(points(lane.id), "0:-6 4:-20", "c takes a typed value")
  T.keys("b")
  eq(paw.cursor.beat, 0, "b goes to the previous point")
  T.keys("w")
  eq(paw.cursor.beat, 4, "w to the next")
  T.keys("x")
  eq(points(lane.id), "0:-6", "x removes the point")
  eq(#t:clips(), 0, "and no clip was touched")
  T.keys("<leader>at")
  eq(api.lane_get(lane.id).enabled, false, "Space at bypasses the lane the cursor is on")
  has(screen(120, 30), "bypass", "the header says so")
end)

test("j and k walk lane rows; Space aa opens and closes them", function()
  local t, other = lane_setup()
  local lane = t:automate("volume")
  t:automate("pan")
  T.keys("<leader>aa")
  eq(paw.lanes.is_open(t), true, "Space aa opens them")
  T.keys("j")
  eq(paw.cursor.lane_id(), lane.id, "j goes onto the first lane")
  T.keys("jj")
  eq(paw.cursor.track_id(), other.id, "and past the lanes to the next track")
  eq(paw.cursor.lane_id(), nil, "on the track itself")
  T.keys("k")
  eq(paw.cursor.lane_id() ~= nil, true, "k comes back onto a lane")
  paw.cursor.set_track(t)
  T.keys("<leader>aa")
  eq(paw.lanes.is_open(t), false, "Space aa again closes them")
  eq(#paw.groups.rows({ lanes = true }), 2, "only the tracks are rows")
end)

test("in a selection on a lane row, points move and go together", function()
  local t = lane_setup()
  local lane = t:automate("volume")
  lane:set_points({ { 0, -6 }, { 1, -3 }, { 2, 0 }, { 6, -10 } })
  api.undo_checkpoint()
  paw.lanes.open(t)
  paw.cursor.set_track(t.id, lane.id)
  T.keys("vllx")
  eq(points(lane.id), "6:-10", "x removes the points in the stretch selected")
  paw.undo()
  paw.cursor.set_track(t.id, lane.id)
  paw.cursor.set_beat(0)
  T.keys("vlL")
  eq(points(lane.id), "1:-6 2:-3 6:-10", "L moves them a grid step later, onto the place of the one at 2")
end)

test("automation lanes as rows are drawn at 80 columns without spilling", function()
  local t = lane_setup()
  t:automate("volume"):set_points({ { 0, -20 }, { 4, 0 } })
  paw.lanes.open(t)
  local text = screen(80, 24)
  has(text, "↳ Volume", "the lane row")
  for line in text:gmatch("[^\n]+") do
    eq(api.str_width(line) <= 80, true, "a line fits: " .. line)
  end
end)

-- Fades and colour ------------------------------------------------------------

test("Space cf asks for the clip's fades; grC chooses the track's colour", function()
  start()
  local t = paw.add_track({ name = "Audio" })
  local clip = t:add_clip({ start = 0, file = "tests/fixtures/tone-mono-8k.wav" })
  paw.cursor.set_track(t)
  paw.cursor.set_beat(0)
  clip.length = 4
  T.keys("<leader>cf1 0.5<CR>")
  eq(clip.fade_in .. "/" .. clip.fade_out, "1/0.5", "in and out")
  T.keys("<leader>cf0.25<CR>")
  eq(clip.fade_in .. "/" .. clip.fade_out, "0.25/0.25", "one length for both")
  T.keys("grC")
  eq(pick.state() and pick.state().title, "Colour of Audio", "the colour picker")
  T.keys("teal<CR>")
  local theme = require("paw.theme")
  local teal
  for i, name in ipairs(theme.hue_names) do
    if name == "teal" then teal = theme.hues[i] end
  end
  eq(t.color, teal, "teal")
  T.keys("grCnone<CR>")
  eq(t.color, nil, "none goes back to the theme's")
end)

-- A time limit on runaway Lua ---------------------------------------------------

--- An endless loop, as an extension's code is.
local function endless()
  return paw.limit.untrusted(loadstring("return function() local x = 0 while true do x = x + 1 end end")())
end

--- Read the messages, as a person would, so that the key line stops
--- mentioning the errors these tests make.
local function read_errors()
  paw.cmd("messages")
  paw.ui.close()
end

local function last_error()
  for i = #paw.ui.messages, 1, -1 do
    if paw.ui.messages[i].level == "error" then return paw.ui.messages[i].text end
  end
  return ""
end

test("a key whose handler never returns is stopped with an error naming it", function()
  start()
  local limit = paw.opt.lua_limit
  paw.opt.lua_limit = 300
  T.expect_error("the key gZ %(zz runaway%) ran for more than")
  paw.keymap.set("gZ", endless(), { view = "arrange", desc = "zz runaway" })
  paw._kernel.key("g")
  paw._kernel.key("Z")
  paw.opt.lua_limit = limit
  paw.keymap.del("gZ", { view = "arrange" })
  has(last_error(), "the key gZ (zz runaway) ran for more than 0.3 s", "the error names the key")
  paw._kernel.key("j")
  eq(paw.keymap.mode, "n", "keys work again afterwards")
  read_errors()
end)

test("the limit reaches into compiled code, so extensions are compiled", function()
  eq(api.limit_async, true, "this build's LuaJIT looks for hooks in compiled loops")
  local hot =
    paw.limit.untrusted(loadstring("return function(n) local x = 0 for i = 1, n do x = x + i end return x end")())
  local traces = 0
  local function count() traces = traces + 1 end
  jit.attach(count, "trace")
  hot(100000)
  jit.attach(count)
  eq(traces > 0, true, "a loop in untrusted code was compiled")
end)

test("a command and a timer that run away are stopped too", function()
  start()
  local limit = paw.opt.lua_limit
  paw.opt.lua_limit = 300
  T.expect_error("the command `zz_forever` ran for more than")
  T.expect_error("a timer ran for more than")
  paw.command("zz_forever", endless(), { desc = "never ends" })
  paw.limit.guard("test", paw.commands.run, "zz_forever")
  has(last_error(), "the command `zz_forever` ran for more than", "a command")
  paw.defer(endless())
  paw.wait(50)
  has(last_error(), "a timer ran for more than", "a timer")
  paw.opt.lua_limit = limit
  read_errors()
end)

test("time spent waiting in the kernel does not count against a callback", function()
  start()
  local limit = paw.opt.lua_limit
  paw.opt.lua_limit = 150
  local before, reached = #paw.ui.messages, false
  paw.limit.guard("test", function()
    paw.api.wait(400)
    -- Enough work afterwards for the clock to be looked at again.
    local x = 0
    for i = 1, 400000 do
      x = x + i % 3
    end
    paw.limit.unhurried(function()
      local till = paw.api.now() + 300
      while paw.api.now() < till do
      end
    end)
    for i = 1, 400000 do
      x = x + i % 3
    end
    reached = true
  end)
  paw.opt.lua_limit = limit
  eq(reached, true, "the callback ran to its end")
  for i = before + 1, #paw.ui.messages do
    eq(paw.ui.messages[i].level ~= "error", true, "no error")
  end
end, { live = "it spins in Lua to pass the time limit, which is on the wall clock" })

test(":lua asked for by hand gets far longer than a callback", function()
  start()
  local limit = paw.opt.lua_limit
  paw.opt.lua_limit = 100
  local before = #paw.ui.messages
  paw.limit.guard(
    "test",
    paw.commands.run,
    "lua",
    { "(function() local t = paw.api.now() + 300 while paw.api.now() < t do end return 'done' end)()" }
  )
  paw.opt.lua_limit = limit
  eq(paw.ui.messages[#paw.ui.messages].text, '"done"', "it ran to the end")
  for i = before + 1, #paw.ui.messages do
    eq(paw.ui.messages[i].level ~= "error", true, "no error")
  end
end, { live = "it spins in Lua to pass the time limit, which is on the wall clock" })

-- A budget for each callback, and long work in slices ---------------------------

--- Wait `ms` milliseconds without returning, as slow code does.
local function busy(ms)
  local till = api.now() + ms
  while api.now() < till do
  end
end

--- The `slow:` warnings written since message `from` that match `part`
--- (on a loaded machine, other callbacks can be slow too).
local function slow_since(from, part)
  local out = {}
  for i = from + 1, #paw.ui.messages do
    local m = paw.ui.messages[i]
    if m.text:match("^slow: ") and m.text:find(part) then out[#out + 1] = m end
  end
  return out
end

local function with_budget(ms)
  local was = paw.opt.budget_ms
  paw.opt.budget_ms = ms
  T.after(function() paw.opt.budget_ms = was end)
end

test("a key over paw.opt.budget_ms is named once in :messages, with its time", function()
  start()
  with_budget(5)
  paw.keymap.set("gY", function() busy(20) end, { view = "arrange", desc = "zz slow key" })
  paw.keymap.set("gV", function() busy(1) end, { view = "arrange", desc = "zz quick key" })
  T.after(function()
    paw.keymap.del("gY", { view = "arrange" })
    paw.keymap.del("gV", { view = "arrange" })
  end)
  local before = #paw.ui.messages
  paw.keymap.feed("gY")
  local slow = slow_since(before, "zz ")
  eq(#slow, 1, "one warning")
  eq(slow[1].level, "warn", "a warning")
  has(slow[1].text, "slow: the key gY (zz slow key) ", "it names the keys")
  local ms = tonumber(slow[1].text:match(" (%d+) ms %(budget 5 ms%)$"))
  eq(ms ~= nil and ms >= 20, true, "it gives the time and the budget: " .. slow[1].text)
  paw.keymap.feed("gY")
  paw.keymap.feed("gV")
  eq(#slow_since(before, "zz "), 1, "a second press and a quick key write nothing more")
  read_errors()
end, { live = "it spins in Lua to pass the time limit, which is on the wall clock" })

test("the budget names a slow timer and a slow event handler", function()
  start()
  with_budget(5)
  local id = paw.on("zz.slow_event", function() busy(20) end)
  T.after(function() paw.off(id) end)
  local before = #paw.ui.messages
  paw.emit("zz.slow_event", {})
  paw.defer(function() busy(20) end)
  paw.wait(30)
  local handler, timer = slow_since(before, "zz.slow_event"), slow_since(before, "flow.lua:")
  eq(#handler, 1, "one warning for the event handler")
  has(handler[1].text, "slow: a handler of `zz.slow_event` ", "it names the event")
  eq(#timer, 1, "one warning for the timer")
  has(timer[1].text, "slow: a timer (tests/flow.lua:", "named by where its function is")
  eq(#slow_since(before, "^slow: a timer %d"), 0, "and none for the call around it")
  read_errors()
end, { live = "it spins in Lua to pass the time limit, which is on the wall clock" })

test("a long job runs in slices of at most its time, and a key comes in between", function()
  start()
  local spent, slices, given = 0, 0, {}
  local seen
  paw.keymap.set("gV", function() seen = paw.slices.job("zz job") end, { view = "arrange", desc = "zz look" })
  T.after(function() paw.keymap.del("gV", { view = "arrange" }) end)
  paw.slices("zz job", function(ms)
    given[#given + 1] = ms
    local t0 = api.now()
    busy(math.min(ms, 50 - spent))
    spent, slices = spent + (api.now() - t0), slices + 1
    return spent >= 50
  end)
  -- A key, as the kernel takes it between two timers.
  paw.defer(function() paw.keymap.feed("gV") end, 10)
  T.until_(function() return paw.slices.job("zz job") == nil end, "the job to end")
  for _, ms in ipairs(given) do
    eq(ms, 4, "each slice gets 4 ms")
  end
  eq(slices >= 10, true, "in slices: " .. slices)
  eq(seen ~= nil and seen.slices >= 1, true, "the key ran while the job ran, after a slice")
  for _, job in ipairs(paw.slices.running()) do
    eq(job.name ~= "zz job", true, "the job is gone when it is over")
  end
end, { live = "it spins in Lua to pass the time limit, which is on the wall clock" })

test(
  "the garbage collector ends its cycles in the job collector between keys, and rests while the heap stays",
  function()
    start()
    local collector = require("paw.collector")
    local grow, cycles = collector.grow, collector.cycles
    T.after(function() collector.grow = grow end)
    -- Any heap is past this at the end of a turn.
    collector.grow = 0
    T.until_(function() return collector.cycles > cycles end, "a cycle that the job ended")
    collector.grow = grow
    T.until_(function() return paw.slices.job("collector") == nil end, "the job to end")
    T.next_block(2)
    eq(paw.slices.job("collector"), nil, "turns that make little garbage start no job")
  end
)
