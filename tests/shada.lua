-- Tests of what paw keeps across restarts (paw/shada.tl). Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local test, eq, keys = T.test, T.eq, T.keys
local api = paw.api
local cmdline = require("paw.views.cmdline")

local dir = T.scratch .. "/shada"
os.execute("rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "'")
local counter = 0

--- Keep the files in a folder of this test's own, as the program does when it
--- is not run with --clean; the state is back to the default afterwards.
local function keeping(fn)
  counter = counter + 1
  local file = string.format("%s/user-%d.json", dir, counter)
  paw.shada.use(file)
  local ok, err = xpcall(fn, debug.traceback, file)
  paw.shada.use()
  paw.opt.shada = true
  if not ok then error(err, 0) end
end

--- What a new start has in memory: nothing.
local function forget()
  cmdline.set_history("cmdline", {})
  cmdline.set_history("search", {})
  paw.keymap.search_text = nil
  for name in pairs(paw.keymap.registers) do
    paw.keymap.registers[name] = nil
  end
end

local function here() return paw.cursor.index() .. "@" .. paw.cursor.beat end

test("shada: command and search history, and the search, come back after a restart", function()
  keeping(function()
    local t = T.three_clips()
    t:add_clip({ name = "riff", start = 16, length = 4 })
    keys(":set zoom<CR>")
    keys("gg0/riff<CR>")
    eq(here(), "1@16", "the search found it")
    paw.shada.write()
    forget()
    paw.shada.read()
    keys("gg0")
    keys(":<Up>")
    eq(cmdline.state().before, "set zoom", "<Up> gives the line of the last run")
    keys("<Esc>")
    keys("n")
    eq(here(), "1@16", "n finds the search of the last run")
    keys("/<Up>")
    eq(cmdline.state().before, "riff", "and the search history is there too")
    keys("<Esc>")
  end)
end)

test("shada: a register keeps its clip", function()
  keeping(function()
    local t = T.three_clips()
    keys('"ayic')
    paw.shada.write()
    forget()
    paw.shada.read()
    keys('w"ap')
    eq(T.layout(t), "a@0+4 b@4+4 a@8+4", '"ap puts the clip that was yanked')
  end)
end)

test("shada: a project gets its marks and its cursor back", function()
  keeping(function()
    T.three_clips()
    local path = dir .. "/song"
    paw.project.save(path)
    paw.project.load(path)
    paw.flush()
    paw.ui.focus("arrange")
    keys("0wmaG$")
    local where = here()
    paw.project.new()
    paw.flush()
    eq(paw.keymap.marks("arrange").a, nil, "another project has no mark")
    paw.project.load(path)
    paw.flush()
    eq(here(), where, "the cursor is where it was")
    keys("gg'a")
    eq(here(), "1@4", "'a goes to the mark")
  end)
end)

test("shada: two writers keep the history of both", function()
  keeping(function(file)
    cmdline.set_history("cmdline", { "mine" })
    paw.shada.write()
    -- Another paw writes its line in the meantime.
    local data = api.json_decode(io.open(file, "rb"):read("*a"))
    table.insert(data.histories.cmdline, { t = "theirs", time = os.time() + 5 })
    local out = io.open(file, "wb")
    out:write(api.json_encode(data))
    out:close()
    cmdline.remember("cmdline", "later")
    paw.shada.write()
    local text = {}
    for _, row in ipairs(api.json_decode(io.open(file, "rb"):read("*a")).histories.cmdline) do
      text[#text + 1] = row.t
    end
    eq(table.concat(text, " "), "mine later theirs", "all three, by time")
    eq(table.concat(cmdline.histories().cmdline, " "), "mine later theirs", "and this paw has them")
  end)
end)

test("shada: --clean and shada = false read and write nothing", function()
  local file = api.env().state_dir .. "/shada.json"
  os.remove(file)
  cmdline.set_history("cmdline", { "x" })
  paw.shada.write()
  eq(api.fs_exists(file), false, "under --clean there is no file")
  keeping(function(own)
    paw.opt.shada = false
    paw.shada.write()
    eq(api.fs_exists(own), false, "with shada = false there is no file")
    paw.opt.shada = true
    paw.shada.write()
    eq(api.fs_exists(own), true, "and with it there is")
    paw.opt.shada = false
    cmdline.set_history("cmdline", {})
    paw.shada.read()
    eq(#cmdline.histories().cmdline, 0, "nothing is read when it is off")
  end)
end)
