-- Rules of the command line that the user guide found broken: `:e!` as in
-- Vim, a failure is one clear line and never a stack traceback, value
-- prompts, relative paths and `:cd`, `:set` on a list option.
local T = ...
local test, eq, fresh, keys = T.test, T.eq, T.fresh, T.keys
local api = paw.api

local function start()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
  -- The errors these tests make on purpose count as read when they end,
  -- so that the key line of the tests after them is as it always is.
  T.after(function() paw.emit("command.pre", { name = "messages", command = "messages", args = {} }) end)
end

local function message() return paw.ui.message and paw.ui.message.text or "" end

local function no_trace(what)
  eq(message():find("traceback", 1, true), nil, what .. ": no stack traceback in " .. message())
  eq(message():find("\n", 1, true), nil, what .. ": one line: " .. message())
end

test("an unknown or failing Ex command says so in one line, never with a stack traceback", function()
  start()
  T.expect_error("^no command `nosuchcommand`")
  T.expect_error("^attempt to index local 't'")
  T.expect_error("^the clip is too short$")
  keys(":nosuchcommand<CR>")
  no_trace("an unknown command")
  eq(message():find("no command `nosuchcommand`", 1, true) ~= nil, true, "names it: " .. message())
  paw.command("test.broken", function()
    local t = nil
    return t.field
  end, { desc = "test" })
  keys(":test.broken<CR>")
  no_trace("a command that breaks")
  eq(message():find("attempt to index", 1, true) ~= nil, true, "says what went wrong: " .. message())
  eq(message():find("cmdline_rules.lua:", 1, true) ~= nil, true, "and where, at the end: " .. message())
  paw.command("test.refuses", function() error("the clip is too short", 2) end, { desc = "test" })
  keys(":test.refuses<CR>")
  eq(message(), "the clip is too short", "a reason given on purpose is the whole message")
  paw.commands.put("test.broken", nil)
  paw.commands.put("test.refuses", nil)
end)

test(":e! goes back to the saved project, and the unsaved-work message names commands that exist", function()
  start()
  local path = T.scratch .. "/edit-bang"
  paw.add_track({ name = "Kept" })
  keys(":w " .. path .. "<CR>")
  paw.add_track({ name = "Thrown away" })
  api.undo_checkpoint()
  keys(":e<CR>")
  eq(#paw.tracks(), 2, ":e alone keeps unsaved work")
  local said = message()
  eq(said:find("unsaved work", 1, true) ~= nil, true, "says why: " .. said)
  for name in said:gmatch("`:([^`%s]+)") do
    eq(paw.commands.get(name) ~= nil, true, "the message names :" .. name .. ", which exists")
  end
  keys(":e!<CR>")
  no_trace(":e!")
  eq(#paw.tracks(), 1, ":e! opens the saved project again")
  eq(paw.tracks()[1].name, "Kept", "as it was saved")
  eq(api.project_get().modified, false, "with nothing unsaved")
  -- `:e! other` opens another project without asking.
  paw.add_track({ name = "Again" })
  api.undo_checkpoint()
  keys(":e! " .. path .. "<CR>")
  eq(#paw.tracks(), 1, ":e! with a name opens it, the changes thrown away")
  start()
  keys(":e!<CR>")
  no_trace(":e! without a file")
  eq(message():find("no file yet", 1, true) ~= nil, true, "a project without a file says so: " .. message())
end)

test("a relative name goes beside the project, or to the folder that :cd set; :pwd shows it", function()
  start()
  T.after(function() paw.files.cd(false) end)
  local song = T.scratch .. "/relative/song"
  local other = T.scratch .. "/relative/other"
  os.execute("mkdir -p '" .. song .. "' '" .. other .. "'")
  T.tone("Keys", 1, "C4")
  keys(":w " .. song .. "<CR>")
  keys(":w take2<CR>")
  eq(io.open(T.scratch .. "/relative/take2/project.toml") ~= nil, true, ":w take2 saves beside the project folder")
  keys(":w song<CR>")
  eq(api.project_get("path"), song .. "/project.toml", ":w song goes back beside take2")
  keys(":pwd<CR>")
  eq(message():find(song, 1, true) ~= nil, true, ":pwd names the project's folder: " .. message())
  keys(":render mix.wav wait=true<CR>")
  eq(io.open(song .. "/mix.wav") ~= nil, true, ":render mix.wav renders beside the project")
  keys(":cd " .. other .. "<CR>")
  eq(paw.files.here(), other, ":cd sets the folder")
  keys(":w moved<CR>")
  eq(io.open(other .. "/moved/project.toml") ~= nil, true, "a relative name goes there after :cd")
  keys(":cd ../song<CR>")
  eq(paw.files.here(), song, ":cd takes a name relative to the folder now")
  keys(":cd -<CR>")
  eq(paw.files.here(), other, ":cd - goes back")
  keys(":cd nosuchfolder<CR>")
  eq(paw.files.here(), other, "a folder that is not there changes nothing")
  eq(message():find("not a folder", 1, true) ~= nil, true, "and says so: " .. message())
end)

test(":set sets a list option: a,b, += and -=, and shows it as a list", function()
  start()
  paw.option.define("test_plugins", {})
  T.after(function() paw.opt.test_plugins = {} end)
  keys(":set test_plugins=Surge,Vital<CR>")
  eq(table.concat(paw.opt.test_plugins, "|"), "Surge|Vital", "a list with commas")
  eq(message(), "test_plugins = Surge,Vital", "shown as a list")
  keys(":set test_plugins+=Dexed<CR>")
  eq(table.concat(paw.opt.test_plugins, "|"), "Surge|Vital|Dexed", "+= adds")
  keys(":set test_plugins-=Surge<CR>")
  eq(table.concat(paw.opt.test_plugins, "|"), "Vital|Dexed", "-= takes away")
  keys(":set test_plugins?<CR>")
  eq(message(), "test_plugins = Vital,Dexed", "? shows it")
  keys(":set test_plugins=Dexed<CR>")
  eq(table.concat(paw.opt.test_plugins, "|"), "Dexed", "one item is a list of one")
  keys(":set test_plugins=<CR>")
  eq(#paw.opt.test_plugins, 0, "nothing is an empty list")
  local was = paw.opt.roll_context
  T.after(function() paw.opt.roll_context = was end)
  keys(":set roll_context=3,5<CR>")
  eq(paw.inspect(paw.opt.roll_context), paw.inspect({ 3, 5 }), "numbers in a list are numbers")
  keys(":set roll_context=group<CR>")
  eq(paw.opt.roll_context, "group", "and a word is still a word")
  keys(":set zoom+=2<CR>")
  eq(
    message():find("not a list option", 1, true) ~= nil,
    true,
    "+= on an option that is no list says so: " .. message()
  )
end)

test(":example opens an example or a practice project that comes with paw, with completion", function()
  start()
  local names = {}
  for _, c in ipairs(paw.commands.complete("example ")) do
    names[#names + 1] = c.text or c
  end
  local all = table.concat(names, " ")
  eq(all:find("demo-song", 1, true) ~= nil, true, "the names complete: " .. all)
  eq(all:find("make-music/2-midi-keyboard", 1, true) ~= nil, true, "the practice projects too: " .. all)
  keys(":example demo-song<CR>")
  eq(#paw.tracks() > 0, true, ":example demo-song opens it")
  eq(paw.project.path, nil, "with no file of its own")
  eq(message():find("opened the example demo-song", 1, true) ~= nil, true, "it says so: " .. message())
  keys("u")
  eq(#paw.tracks() > 0, true, "u does not take the example apart")
  local before = #paw.tracks()
  keys(":example 2-midi<CR>")
  eq(#paw.tracks(), before, "the example is unsaved work: another does not replace it")
  keys(":example! 2-midi<CR>")
  eq(
    paw.track("Lead") ~= nil or #paw.tracks() ~= before,
    true,
    ":example! opens the other one, a part of its name enough"
  )
  keys(":example<CR>")
  eq(message():find("which example?", 1, true) ~= nil, true, "alone, it lists them: " .. message())
end)

test("a key typed in the : line asks for no whole frame, unless a range is on the views", function()
  start()
  paw.add_track({ name = "Lead" })
  keys(":")
  local function whole() return api.ui_redraws() - api.ui_line_redraws() end
  local before = whole()
  keys("he")
  eq(whole(), before, "the letters of a command name draw the line and the list only")
  eq(require("paw.views.cmdline").state().before, "he", "and the line has them")
  keys("<BS><BS>1,")
  keys("3")
  eq(whole() > before, true, "a range on the views is a whole frame")
  keys("<Esc>")
end)
