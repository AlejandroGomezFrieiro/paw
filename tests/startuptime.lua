-- Startup profiling: `paw --startuptime FILE` (crates/paw-core/src/startuptime.rs,
-- paw/startuptime.tl) and `:profile` (paw/profile.tl). Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local test, eq = T.test, T.eq
local api = paw.api

local function binary()
  local pipe = io.popen("readlink /proc/" .. api.env().pid .. "/exe")
  local path = pipe:read("*l")
  pipe:close()
  return path
end

-- The folders of a paw started by a test: never the owner's.
local function env(dir)
  return string.format(
    "XDG_RUNTIME_DIR='%s' XDG_STATE_HOME='%s/state' XDG_DATA_HOME='%s/data' XDG_CACHE_HOME='%s/cache' TERM=xterm-256color",
    dir,
    dir,
    dir,
    dir
  )
end

--- The lines of a startuptime file: `{ clock, label, self }`, `self` nil
--- for a line that is not of a sourced item.
local function lines_of(text)
  local out = {}
  for line in text:gmatch("[^\n]+") do
    local clock, a, b, label = line:match("^([%d%.]+)  ([%d%.]+)  ([%d%.]+): (.*)$")
    if clock then
      out[#out + 1] = { clock = tonumber(clock), whole = tonumber(a), self = tonumber(b), label = label }
    else
      clock, a, label = line:match("^([%d%.]+)  ([%d%.]+): (.*)$")
      if clock then out[#out + 1] = { clock = tonumber(clock), label = label } end
    end
  end
  return out
end

local function find(lines, label)
  for _, l in ipairs(lines) do
    if l.label == label then return l end
  end
end

test(
  "startuptime: the terminal's start writes a line for each module, the first frame, and clocks that grow",
  function()
    local dir = T.scratch .. "/startuptime"
    os.execute("mkdir -p '" .. dir .. "'")
    local file = dir .. "/startup.log"
    -- A terminal of its own (a pseudo-terminal of `script`), so that there is a first frame.
    local cmd = string.format(
      "%s '%s' --startuptime '%s' --clean --no-plugins --no-listen --audio null --keys ':q!<CR>'",
      env(dir),
      binary(),
      file
    )
    os.execute(string.format("cd '%s' && timeout 30 script -qec %q /dev/null > /dev/null 2>&1", dir, cmd))
    local lines = lines_of(T.read_file(file) or "")
    eq(lines[1] and lines[1].label, "--- PAW STARTING ---", "the first line")
    eq(lines[#lines] and lines[#lines].label, "--- PAW STARTED ---", "the last line")
    local harmony = find(lines, "require('paw.harmony')")
    eq(harmony ~= nil and harmony.self <= harmony.whole, true, "paw.harmony, its own time within its whole time")
    eq(find(lines, "first frame") ~= nil, true, "the first frame")
    for i = 2, #lines do
      if lines[i].clock < lines[i - 1].clock then error("the clock goes back at " .. lines[i].label) end
    end
  end
)

test("startuptime: an extension of the configuration has a line with its own time", function()
  local dir = T.scratch .. "/startuptime-ext"
  local ext = dir .. "/config/extensions/slowpoke"
  os.execute("mkdir -p '" .. ext .. "/lua/slowpoke'")
  -- 20 ms of its own, and a module that it requires.
  T.write_file(
    ext .. "/init.lua",
    "require('slowpoke.part')\nlocal t = paw.api.now() + 20\nwhile paw.api.now() < t do end\n"
  )
  T.write_file(ext .. "/lua/slowpoke/part.lua", "return {}\n")
  T.write_file(dir .. "/quit.lua", "paw.api.quit(0)\n")
  local file = dir .. "/startup.log"
  os.execute(
    string.format(
      "%s '%s' --startuptime '%s' --config '%s/config' --no-plugins --audio null -l '%s/quit.lua' > /dev/null 2>&1",
      env(dir),
      binary(),
      file,
      dir,
      dir
    )
  )
  local lines = lines_of(T.read_file(file) or "")
  local line = find(lines, "extension slowpoke")
  eq(line ~= nil, true, "a line for the extension")
  eq(line.self >= 20, true, "its own 20 ms: " .. tostring(line.self))
  eq(find(lines, "require('slowpoke.part')") ~= nil, true, "the module it requires has a line of its own")
  eq(find(lines, "the script starts") ~= nil, true, "a script's start ends where the script starts")
end)

test(":profile start, a Lua loop of 50 ms, :profile stop: the loop's function is first in the quickfix list", function()
  T.fresh()
  T.after(function()
    if paw.profile.running() then paw.profile.stop() end
    -- The list made here is not left for the tests after.
    paw.qf.close()
    local s = paw.qf.stack()
    s.lists, s.at = {}, 0
    paw.layout.only()
  end)
  local function busy_loop()
    local x, t = 0, api.now() + 50
    while api.now() < t do
      for i = 1, 1000 do
        x = x + i
      end
    end
    return x
  end
  T.keys(":profile start<CR>")
  eq((paw.profile.running()), true, ":profile start starts it")
  busy_loop()
  T.keys(":profile stop<CR>")
  eq((paw.profile.running()), false, ":profile stop stops it")
  local list = paw.qf.current()
  eq(list.title, "Lua profile", "the quickfix list of the profile")
  local first = list.entries[1]
  eq(first.text:find("busy_loop", 1, true) ~= nil, true, "the loop's function first: " .. first.text)
  eq(
    paw.qf.where(first):match("tests/startuptime%.lua:%d+$") ~= nil,
    true,
    "with its file and line: " .. paw.qf.where(first)
  )
end)
