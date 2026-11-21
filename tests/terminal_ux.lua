-- Terminal fixes found by evaluating the program: wrapping of long words in
-- the pager, `:edit` with buffer names, new windows and tabs, searching keys
-- and commands, prompts that come selected, `:set` on unknown options, the
-- quickfix key line, bare extension names, the cursor on open, autosave of
-- imported work. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api
local L = paw.layout

local W, H = 160, 48
local initial = L.capture()

-- Empty windows made here are forgotten with their buffers.
local function clear_empty()
  for id, buf in pairs(L.buffers) do
    if buf.type == "empty" then L.buffers[id] = nil end
  end
end

local function start()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do paw.ui.close() end
  L.restore(initial)
  clear_empty()
  paw.ui.focus("arrange")
  T.after(function()
    paw.keymap.feed("<Esc><Esc>")
    while paw.ui.float do paw.ui.close() end
    L.restore(initial)
    clear_empty()
    paw.ui.focus("arrange")
  end)
end

local function screen() return table.concat(api.ui_snapshot(W, H), "\n") end
local function last_message() return paw.ui.messages[#paw.ui.messages].text end
local function windows()
  local out = {}
  for _, win in ipairs(L.windows(paw.ui.layout)) do out[#out + 1] = L.buf_of(win).name end
  return table.concat(out, " ")
end

test("the pager breaks a word longer than its width instead of hanging", function()
  local wrap = paw.ui.views.pager.wrap
  local long = "saved " .. string.rep("a/", 40) .. "song.json"
  local rows = wrap(long, 20)
  for _, row in ipairs(rows) do eq(#row <= 20, true, "every row fits: " .. row) end
  eq((table.concat(rows):gsub("%s", "")), (long:gsub("%s", "")), "nothing is lost")
  eq(#wrap(string.rep("x", 100), 10) > 1, true, "one long word is cut")
  eq(wrap("one two three four five six seven", 12)[2], "  three four", "words still break at spaces")
end)

test(":messages shows a message with a long path", function()
  start()
  paw.notify("saved /" .. string.rep("long-directory-name/", 12) .. "song.json")
  paw.cmd("messages")
  eq(screen():find("song.json", 1, true) ~= nil, true, "the end of the path is on the screen")
  paw.ui.close()
end)

test(":edit and :e show a known buffer by name even when there is unsaved work", function()
  start()
  paw.add_track({ name = "Keys" })
  paw.ui.show("mixer")
  paw.commands.exec("e mixer")
  eq(L.buf_of(L.current()).name, "mixer", "`:e` shows the mixer here")
  paw.commands.exec("edit arrange")
  eq(L.buf_of(L.current()).name, "arrange", "`:edit` shows the arrange view here, not the project guard")
  eq(api.project_get().path, nil, "no file was read")
  paw.commands.exec("edit paw://tracks")
  eq(L.buf_of(L.current()).type, "textbuf", "an address opens its text buffer")
  eq(#api.track_list(), 1, "the work is still there")
end)

test("`,m` in a window that is only the mixer leaves the mixer there, as Ctrl-w c does", function()
  start()
  paw.ui.show("mixer")
  paw.ui.focus("mixer")
  L.only()
  eq(windows(), "mixer", "the mixer alone")
  paw.keymap.feed("<leader>mm")
  eq(windows(), "mixer", "the last window does not close, and no arrange view comes back")
  eq(paw.ui.message and paw.ui.message.text:find("last window", 1, true) ~= nil, true, "it says so")
  paw.keymap.feed("<C-w>c")
  eq(windows(), "mixer", "nor with Ctrl-w c")
end)

test(":vs and :sp without a name show the same buffer as far as a view can", function()
  start()
  paw.cmd("vs")
  eq(windows(), "arrange arrange", "the arrange view shows in both windows, each with its own scroll")
  paw.cmd("only")
  paw.commands.exec("e mixer")
  paw.cmd("sp")
  eq(windows(), "mixer mixer", "the mixer shows in both windows, each with its own scroll")
  paw.cmd("only")
  paw.commands.exec("e eventlist")
  paw.cmd("sp")
  eq(windows():find("[No Name]", 1, true) ~= nil, true, "a view shown in one window at a time leaves an empty window")
  eq(screen():find("Recent projects", 1, true) ~= nil, true, "which shows the start page")
  paw.cmd("only")
  paw.commands.exec("e paw://tracks")
  local buf = L.buf_of(L.current())
  paw.cmd("vs")
  eq(L.buf_of(L.current()), buf, "a text buffer shows in both windows")
  eq(#L.windows(paw.ui.layout), 2, "two windows")
  paw.cmd("vnew")
  eq(L.buf_of(L.current()).type, "empty", ":vnew is always empty")
end)

test("empty windows are numbered among those there are, from none", function()
  start()
  paw.cmd("tabnew")
  eq(L.tab_title(paw.ui.tabs[2]), "[No Name]", "the first is not numbered")
  paw.cmd("tabnew")
  eq(L.tab_title(paw.ui.tabs[3]), "[No Name 2]", "the second is")
  paw.cmd("tabclose")
  paw.cmd("tabclose")
  paw.cmd("tabnew")
  eq(L.tab_title(paw.ui.tabs[2]), "[No Name]", "the numbers are free again once the windows are closed")
  eq(L.tab_title(paw.ui.tabs[1]), "arrange", "the first tab is named after its buffer")
  paw.cmd("tabclose")
end)

local function ranked(source, query)
  local src = paw.pick.sources[source]
  src = type(src) == "function" and src() or src
  local out = {}
  for _, r in ipairs(paw.pick.filter(query, src.items(), src.format, src.primary)) do out[#out + 1] = r end
  return out
end

test("`?` in the mixer finds the arrange view's `,s` for `send`, and says it is an arrange key", function()
  start()
  paw.ui.show("mixer")
  paw.ui.focus("mixer")
  local list = ranked("keys", "send")
  local found
  for _, r in ipairs(list) do
    if r.item.other == "arrange" and r.item.map.lhs == "<leader>ts" then found = r end
  end
  eq(found ~= nil, true, "`,s` is listed")
  eq(found.text:find("arrange view", 1, true) ~= nil, true, "as a key of the arrange view")
  eq(list[1].item.map.lhs:find("<C%-w>") == nil, true, "and the window keys do not come first")
end)

test("`,,` puts the command named like the query first", function()
  start()
  eq(ranked("commands", "arrange")[1].item.name, "arrange", "`:arrange` is first for arrange")
  eq(ranked("commands", "send")[1].item.name, "send", "and `:send` for send")
  eq(ranked("commands", "mixer")[1].item.name, "mixer", "and `:mixer` for mixer")
end)

test("a prompt with text comes with the text selected, so that typing replaces it", function()
  start()
  local got
  paw.ui.input({ prompt = "Name: ", text = "Track 1" }, function(text) got = text end)
  eq(require("paw.views.cmdline").state().selected, true, "selected")
  paw.keymap.feed("Lead<CR>")
  eq(got, "Lead", "typing replaced it")
  paw.ui.input({ prompt = "Name: ", text = "Track 1" }, function(text) got = text end)
  paw.keymap.feed("<CR>")
  eq(got, "Track 1", "Enter keeps it")
  paw.ui.input({ prompt = "Name: ", text = "Track 1" }, function(text) got = text end)
  paw.keymap.feed("<Right>s<CR>")
  eq(got, "Track 1s", "a motion key takes the selection off, and typing adds")
  paw.ui.input({ prompt = "Name: ", text = "Track 1" }, function(text) got = text end)
  paw.keymap.feed("<C-u>x<CR>")
  eq(got, "x", "Ctrl-u clears it")
  paw.ui.input({ prompt = "Name: ", text = "Track 1" }, function(text) got = text end)
  paw.keymap.feed("<BS>y<CR>")
  eq(got, "y", "backspace clears it")
  paw.ui.input({ prompt = ":", text = "set " }, function(text) got = text end)
  paw.keymap.feed("zoom<CR>")
  eq(got, "set zoom", "the command line's text is not selected")
end)

test("`grn` asks for the name with the old one selected", function()
  start()
  paw.add_track({ name = "Track 1" })
  paw.keymap.feed("grn")
  paw.keymap.feed("Lead<CR>")
  eq(paw.tracks()[1].name, "Lead", "the name was replaced")
end)

test(":set says an unknown option is an error, and `?` shows a known one", function()
  start()
  paw.commands.exec("set master?")
  eq(last_message(), "E518: Unknown option: master", "unknown")
  eq(paw.ui.messages[#paw.ui.messages].level, "error", "as an error")
  paw.commands.exec("set zoom?")
  eq(last_message(), "zoom = " .. tostring(paw.opt.zoom), "a known option is shown")
  paw.commands.exec("set nosuch 3")
  eq(last_message(), "E518: Unknown option: nosuch", "setting one is the same error")
end)

test(":set nofollow, :set follow, :set follow! and :set invfollow, as in Vim", function()
  start()
  local follow, zoom = paw.opt.follow, paw.opt.zoom
  T.after(function() paw.opt.follow, paw.opt.zoom = follow, zoom end)
  paw.keymap.feed(":set nofollow<CR>")
  eq(paw.opt.follow, false, "no sets it false")
  eq(last_message(), "follow = false", "and says so")
  paw.keymap.feed(":set follow<CR>")
  eq(paw.opt.follow, true, "the name alone sets it true")
  paw.keymap.feed(":set follow!<CR>")
  eq(paw.opt.follow, false, "! flips it")
  paw.keymap.feed(":set invfollow<CR>")
  eq(paw.opt.follow, true, "inv flips it")
  paw.keymap.feed(":set nozoom<CR>")
  eq(last_message(), "zoom is not a true/false option", "no on a number")
  paw.keymap.feed(":set zoom<CR>")
  eq(last_message(), "zoom = " .. tostring(paw.opt.zoom), "a number's name alone shows it")
  paw.keymap.feed(":set follow?<CR>")
  eq(paw.opt.follow, true, "? does not set it")
end)

test("a bare extension name opens its main view, or suggests what it could mean", function()
  local ran = 0
  paw.command("uxext.open", function() ran = ran + 1 end, { desc = "the view" })
  paw.command("uxext.other", function() end, { desc = "another" })
  paw.command("uxonly.first", function() end, { desc = "one" })
  paw.commands.exec("uxext")
  eq(ran, 1, "`:uxext` ran `uxext.open`")
  local ok, why = pcall(paw.commands.exec, "uxonly")
  eq(ok, false, "without one it is still an error")
  eq(tostring(why):find("did you mean :uxonly.first", 1, true) ~= nil, true, "which suggests: " .. tostring(why))
end)

-- A Standard MIDI file of one note.
local function midi_file()
  local path = T.scratch .. "/ux.mid"
  local f = assert(io.open(path, "wb"))
  local data = "\0\144\60\64" .. "\96\128\60\0" .. "\0\255\47\0"
  f:write("MThd\0\0\0\6\0\0\0\1\0\96", "MTrk\0\0\0", string.char(#data), data)
  f:close()
  return path
end

test("opening a project puts the cursor back at its start", function()
  start()
  paw.add_track({ name = "A" })
  paw.add_track({ name = "B" })
  paw.cursor.set_track(paw.tracks()[2])
  paw.cursor.set_beat(7)
  paw.commands.exec("open! " .. midi_file())
  paw.flush()
  eq(paw.cursor.beat, 0, "at the start")
  eq(paw.cursor.index(), 1, "on the first track")
end)

test("autosave keeps a copy of an imported project that was never modified", function()
  start()
  local dir = T.scratch .. "/ux-autosave"
  os.execute("mkdir -p '" .. dir .. "'")
  local old = paw.autosave.dir
  paw.autosave.dir = dir
  T.after(function() paw.autosave.dir = old end)
  paw.commands.exec("open! " .. midi_file())
  paw.flush()
  eq(api.project_get().modified, false, "nothing was changed")
  eq(paw.project.unsaved(), true, "yet it is not on disk")
  eq(paw.autosave.copy() ~= nil, true, "a copy is written")
end)
