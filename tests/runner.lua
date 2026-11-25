-- The runner of the tests (tests/suite.lua) on test files of a fixture: a
-- second paw runs the runner on a folder with test files, a quarantine list
-- and a list of the kernel API of its own (PAW_TEST_FIXTURE), and the test
-- reads what it printed and the files that it wrote.
local T = ...
local test, eq = T.test, T.eq
local ffi = require("ffi")

pcall(ffi.cdef, "long readlink(const char *path, char *buf, size_t size);")

-- The paw that runs this suite: the child runs the same binary.
local function this_paw()
  local buf = ffi.new("char[4096]")
  local n = tonumber(ffi.C.readlink("/proc/self/exe", buf, 4096))
  assert(n > 0, "the path of the paw binary")
  return ffi.string(buf, n)
end

local runs = 0

--- Run the runner on a fixture folder that holds `files` (name -> text),
--- with `env` (name -> value) in its environment, and `words` (the words of
--- `only`, one on each line) if given. In a value of `env`, `<dir>` is the
--- fixture folder. Gives what it printed, and whether it passed.
local function run_fixture(files, env, words)
  runs = runs + 1
  local dir = T.scratch .. "/runner-" .. runs
  os.execute("mkdir -p '" .. dir .. "/home'")
  for name, text in pairs(files) do
    T.write_file(dir .. "/" .. name, text)
  end
  -- The child gets folders of its own, and none of the settings of this run.
  local vars = {
    "env -u PAW_TEST_PART -u PAW_TEST_LIST -u PAW_TEST_LIVE -u PAW_TEST_REPEAT -u PAW_TEST_SHUFFLE -u PAW_BLESS",
    "PAW_TEST_FIXTURE='" .. dir .. "'",
    "HOME='" .. dir .. "/home'",
  }
  for _, name in ipairs({ "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME" }) do
    vars[#vars + 1] = name .. "='" .. dir .. "/" .. name:lower() .. "'"
  end
  for name, value in pairs(env or {}) do
    vars[#vars + 1] = name .. "='" .. value:gsub("<dir>", dir) .. "'"
  end
  local pipe = io.popen(
    table.concat(vars, " ")
      .. " '"
      .. this_paw()
      .. "' --clean --no-plugins --audio null --clock manual -l tests/suite.lua"
      .. (words and (" '" .. words .. "'") or "")
      .. ' 2>&1; echo "exit $?"'
  )
  -- LuaJIT's close of a pipe does not give the code of the process: the
  -- shell prints it on the last line.
  local printed = pipe:read("*a")
  pipe:close()
  local code = printed:match("\nexit (%d+)\n$")
  return printed, code == "0"
end

-- A fixture file: a test that passes, a test that skips, a test that always
-- fails, and a quarantined test that passes.
local FOUR = [[
local T = ...
T.test("a test that passes", function() end)
T.test("a test that skips", function() return "no such tool here" end)
T.test("a test that always fails", function() error("the flaky thing") end)
T.test("a quarantined test that passes", function() end)
]]

test("a failure of a quarantined test is reported, and the run does not fail", function()
  local printed, passed = run_fixture({
    ["four.lua"] = FOUR,
    ["quarantine.txt"] = "# the list\na test that always fails\tthe fix of the flaky thing\n"
      .. "a quarantined test that passes\tanother fix\n",
  })
  eq(
    printed:find("quarantined  a test that always fails (waits for: the fix of the flaky thing)", 1, true) ~= nil,
    true,
    printed
  )
  eq(printed:find("ok    a quarantined test that passes (quarantined, and it passed", 1, true) ~= nil, true, printed)
  eq(printed:match("\n([^\n]*)\nexit %d+\n$"), "all passed", "the last line")
  eq(passed, true, "the run passes")
end)

test("a line of the quarantine list with no fix fails the run, and names the line", function()
  local printed, passed = run_fixture({
    ["four.lua"] = FOUR,
    ["quarantine.txt"] = "# the list\na test that always fails\tthe fix\na test that skips\t \n",
  })
  eq(
    printed:find("quarantine.txt:3 has no tab and fix after the name of the test: a test that skips", 1, true) ~= nil,
    true,
    printed
  )
  eq(passed, false, "the run fails")
end)

test("a binary that lacks a function of the runtime's kernel API fails at the start", function()
  local printed, passed = run_fixture({
    ["four.lua"] = FOUR,
    ["declarations.txt"] = "function paw.api.version_of_tomorrow(opts) end\nfunction paw.api.part_add(opts) end\n",
  })
  eq(
    printed:find("the paw binary is older than the runtime: it has no paw.api.version_of_tomorrow.", 1, true) ~= nil,
    true,
    printed
  )
  eq(printed:find("a test that passes", 1, true), nil, "no test ran")
  eq(passed, false, "the run fails")
end)

-- Two parts: the harness of cargo nextest runs each one in a paw of its own.
local TWO_PARTS = {
  ["a.lua"] = 'local T = ...\nT.test("a test of part a", function() end)\n'
    .. 'T.test("a live test of part a", function() end, { live = "it needs the wall clock" })\n',
  ["b.lua"] = 'local T = ...\nT.test("a test of part b", function() end)\n',
}

test("PAW_TEST_PART runs the tests of one part, and names the live tests it leaves", function()
  local printed, passed = run_fixture(TWO_PARTS, { PAW_TEST_PART = "<dir>/a.lua" })
  eq(passed, true, printed)
  eq(printed:find("ok    a test of part a", 1, true) ~= nil, true, printed)
  eq(printed:find("part b", 1, true), nil, "the test of the other part: " .. printed)
  eq(printed:match("live tests: %d+"), "live tests: 1", "the live tests for the live pass")
end)

test("a part with no test file fails the run, and names the part", function()
  local printed, passed = run_fixture(TWO_PARTS, { PAW_TEST_PART = "<dir>/c.lua" })
  eq(passed, false, "the run fails")
  eq(printed:find("c.lua, and no test file is in that part", 1, true) ~= nil, true, printed)
end)

test("the list gives each part that has a test of the words, and runs no test", function()
  local printed, passed = run_fixture(TWO_PARTS, { PAW_TEST_LIST = "1" }, "live test\nnothing")
  eq(passed, true, printed)
  local parts = {}
  for part in printed:gmatch("part\t[^\n]*/([^/\n]+)\n") do
    parts[#parts + 1] = part
  end
  eq(parts, { "a.lua" }, "the parts: " .. printed)
  eq(printed:find("ok    ", 1, true), nil, "no test ran")
end)

test("repeat stops at the first run that fails, and names it", function()
  local printed, passed = run_fixture({
    -- The count is global: each run loads the file again.
    ["second.lua"] = 'local T = ...\nT.test("a test that fails on its second run", function()\n'
      .. '  _G.runs = (_G.runs or 0) + 1\n  assert(_G.runs < 2, "the second run")\nend)\n',
  }, { PAW_TEST_REPEAT = "20" })
  eq(printed:find("repeat: run 2 of 20 failed", 1, true) ~= nil, true, printed)
  eq(passed, false, "the run fails")
end)

test("each run of repeat loads the test files again", function()
  local printed, passed = run_fixture({
    -- What the file keeps at its top, as a test file keeps the module of
    -- its extension, starts again with each run.
    ["fresh.lua"] = 'local T = ...\nlocal used = false\nT.test("a test that needs a fresh file", function()\n'
      .. '  assert(not used, "the file of an earlier run")\n  used = true\nend)\n',
  }, { PAW_TEST_REPEAT = "3" })
  eq(passed, true, printed)
end)

test("a shuffle prints its seed, and the same seed gives the same order", function()
  local names = {}
  for i = 1, 6 do
    names[i] = string.format('T.test("test %d", function() end)', i)
  end
  local files = {
    ["a.lua"] = "local T = ...\n" .. table.concat(names, "\n", 1, 3),
    ["b.lua"] = "local T = ...\n" .. table.concat(names, "\n", 4, 6),
  }
  local function order(printed)
    local out = {}
    for n in printed:gmatch("\nok    test (%d)") do
      out[#out + 1] = n
    end
    return table.concat(out, " ")
  end
  local first = run_fixture(files, { PAW_TEST_SHUFFLE = "7" })
  local again = run_fixture(files, { PAW_TEST_SHUFFLE = "7" })
  eq(first:match("shuffle seed %d+"), "shuffle seed 7", "the seed")
  eq(order(first), order(again), "the order of the same seed")
  eq(order(first) ~= "1 2 3 4 5 6", true, "the order is shuffled: " .. order(first))
end)

test("the leak check names a key, a hook and a timer that a test file leaves", function()
  local printed, passed = run_fixture({
    ["leak.lua"] = [[
local T = ...
T.test("a test that leaves state", function()
  paw.keymap.set("gZ", function() end, { desc = "zz leaked key" })
  paw.on("zz.leaked", function() end)
  paw.defer(function() end, 60000)
end)
]],
  })
  eq(passed, false, "the run fails")
  local changed = printed:match("leak%.lua leaves no state behind\n%s*changed: ([^\n]*)") or ""
  for _, kind in ipairs({ "keys", "hooks", "timers" }) do
    eq(changed:find(kind .. " ", 1, true) ~= nil, true, kind .. " in: " .. printed)
  end
end)

-- The harness of nextest (tests/harness) gives each paw of a run its path.
local harness = os.getenv("PAW_TEST_HARNESS")

--- Run the harness binary with `args`, after the shell text `env`. Gives
--- what it printed (with its errors) and its exit code on the last line.
local function run_harness(env, args)
  local pipe = io.popen(env .. " '" .. harness .. "' " .. args .. ' 2>&1; echo "exit $?"')
  local printed = pipe:read("*a")
  pipe:close()
  return printed
end

test("the harness of the suite refuses to start inside a run of the suite", function()
  if not harness then return "the run did not start from the harness of nextest" end
  eq(
    run_harness("PAW_TEST_IN_SUITE=1", "--list"),
    "the Lua suite does not start inside a run of the Lua suite (PAW_TEST_IN_SUITE is set)\nexit 2\n",
    "what it printed"
  )
end)

test("the harness lists the parts of the runner", function()
  if not harness then return "the run did not start from the harness of nextest" end
  -- With no words, the list reads the folders and starts no paw.
  local printed = run_harness("env -u PAW_TEST_IN_SUITE -u PAW_TEST_WORDS", "--list --format terse")
  local listed = {}
  for part in printed:gmatch("([^\n]+): test\n") do
    listed[#listed + 1] = part
  end
  eq(listed, T.parts(), "the parts of the harness and of tests/suite.lua")
end)

test("tests/tools/suite.sh refuses to start inside a run of the suite", function()
  -- A paw of the suite has PAW_TEST_IN_SUITE: a test that starts the suite
  -- again would start paw processes without end. The limit on processes
  -- stops the machine from a flood if the guard goes. Linux counts the
  -- threads of this user against it: the threads of now and 200 more.
  local pipe = io.popen(
    [[bash -c 'ulimit -u $(( $(ps -u "$(id -u)" -L --no-headers | wc -l) + 200 )) &&
      PAW_TEST_IN_SUITE=1 tests/tools/suite.sh only x' 2>&1; echo "exit $?" ]]
  )
  local printed = pipe:read("*a")
  pipe:close()
  eq(printed, "suite.sh: the suite does not start inside a run of the suite\nexit 2\n", "what it printed")
end)
