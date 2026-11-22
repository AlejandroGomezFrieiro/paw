-- The check against tests that depend on time (tools/testlint.lua) and its
-- allow-list, tests/timing-allowed.txt. Loaded by tests/suite.lua with its
-- helpers.
local T = ...
local test, eq = T.test, T.eq
local lint = dofile("tools/testlint.lua")

test(
  "testlint: no test sleeps, reads the clock or checks a speed beyond the allow-list",
  function() eq(table.concat(lint.check("."), "\n"), "", "the problems") end
)

test("testlint: a new api.sleep in a test file fails, and a smaller count asks for a smaller line", function()
  -- The names are cut in two, so that the check does not count this file.
  local sleep, wait = "api." .. "sleep(", "paw." .. "wait("
  local root = T.scratch .. "/testlint"
  os.execute("mkdir -p '" .. root .. "/tests'")
  T.write_file(root .. "/tests/timing-allowed.txt", "# a comment\ntests/old.lua " .. wait .. " 2\n")
  T.write_file(root .. "/tests/old.lua", wait .. "5)\n-- " .. wait .. "5) in a comment\n")
  T.write_file(root .. "/tests/new.lua", "local api = paw.api\n" .. sleep .. "10)\n")
  eq(
    table.concat(lint.check(root), "\n"),
    table.concat({
      "tests/new.lua: 1 of `"
        .. sleep
        .. "`, 0 allowed. A test does not sleep, read the clock or check a speed:"
        .. " wait for a state, or measure in bench/ (docs/how-to/run-the-tests.md)",
      "tests/old.lua: 1 of `"
        .. wait
        .. "` now: make the line `tests/old.lua "
        .. wait
        .. " 1` in tests/timing-allowed.txt",
    }, "\n"),
    "the problems"
  )
end)
