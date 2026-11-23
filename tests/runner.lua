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
--- with `env` (name -> value) in its environment. Gives what it printed,
--- whether it passed, and the folder of the files of the run.
local function run_fixture(files, env)
  runs = runs + 1
  local dir = T.scratch .. "/runner-" .. runs
  local out = dir .. "/out"
  os.execute("mkdir -p '" .. out .. "' '" .. dir .. "/home'")
  for name, text in pairs(files) do
    T.write_file(dir .. "/" .. name, text)
  end
  -- The child gets folders of its own, and none of the settings of this run.
  local vars = {
    "env -u PAW_TEST_SHARD -u PAW_TEST_LIVE -u PAW_TEST_REPEAT -u PAW_TEST_SHUFFLE -u PAW_BLESS",
    "PAW_TEST_FIXTURE='" .. dir .. "'",
    "PAW_TEST_OUT='" .. out .. "'",
    "HOME='" .. dir .. "/home'",
  }
  for _, name in ipairs({ "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME" }) do
    vars[#vars + 1] = name .. "='" .. dir .. "/" .. name:lower() .. "'"
  end
  for name, value in pairs(env or {}) do
    vars[#vars + 1] = name .. "='" .. value .. "'"
  end
  local pipe = io.popen(
    table.concat(vars, " ")
      .. " '"
      .. this_paw()
      .. '\' --clean --no-plugins --audio null --clock manual -l tests/suite.lua 2>&1; echo "exit $?"'
  )
  -- LuaJIT's close of a pipe does not give the code of the process: the
  -- shell prints it on the last line.
  local printed = pipe:read("*a")
  pipe:close()
  local code = printed:match("\nexit (%d+)\n$")
  return printed, code == "0", out
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
    ["declarations.txt"] = "function paw.api.version_of_tomorrow(opts) end\nfunction paw.api.track_add(opts) end\n",
  })
  eq(
    printed:find("the paw binary is older than the runtime: it has no paw.api.version_of_tomorrow.", 1, true) ~= nil,
    true,
    printed
  )
  eq(printed:find("a test that passes", 1, true), nil, "no test ran")
  eq(passed, false, "the run fails")
end)

test("the TAP file lists each test with its result and the reason of a skip", function()
  local _, _, out = run_fixture({
    ["four.lua"] = FOUR,
    ["quarantine.txt"] = "a test that always fails\tthe fix\n",
  })
  local tap = T.read_file(out .. "/tap.lines")
  local results = {}
  for line in tap:gmatch("[^\n]+") do
    if line:match("ok %- a ") then results[#results + 1] = line end
  end
  eq(results, {
    "ok - a test that passes",
    "ok - a test that skips # SKIP no such tool here",
    "not ok - a test that always fails # TODO quarantined, waits for: the fix",
    "ok - a quarantined test that passes",
  }, "the results")
end)

test("times.txt has one line for each test file", function()
  local _, _, out = run_fixture({ ["a.lua"] = FOUR, ["b.lua"] = FOUR })
  local files = {}
  for name in T.read_file(out .. "/times.txt"):gmatch("%d+\t([^\n]+)") do
    files[#files + 1] = name:match("[^/]+$")
  end
  table.sort(files)
  eq(files, { "a.lua", "b.lua" }, "the files")
end)

test("repeat stops at the first run that fails, and names it", function()
  local printed, passed = run_fixture({
    ["second.lua"] = 'local T = ...\nlocal runs = 0\nT.test("a test that fails on its second run", function()\n'
      .. '  runs = runs + 1\n  assert(runs < 2, "the second run")\nend)\n',
  }, { PAW_TEST_REPEAT = "20" })
  eq(printed:find("repeat: run 2 of 20 failed", 1, true) ~= nil, true, printed)
  eq(passed, false, "the run fails")
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
