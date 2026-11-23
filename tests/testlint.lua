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

test(
  "testlint: a test that reads the home folder or the user name fails, and the allow-list cannot let it pass",
  function()
    -- The names are cut in two, so that the check does not count this file.
    local home, user, var = "os.getenv(" .. '"HOME")', "os.getenv(" .. '"USER")', "var_os(" .. '"HOME")'
    local root = T.scratch .. "/testlint-machine"
    os.execute("mkdir -p '" .. root .. "/tests' '" .. root .. "/crates/x/tests'")
    T.write_file(root .. "/tests/timing-allowed.txt", "tests/a.lua " .. user .. " 1\n")
    T.write_file(root .. "/tests/a.lua", "local h = " .. home .. "\nlocal p = '/" .. "home/me/x.wav'\n")
    T.write_file(root .. "/crates/x/tests/b.rs", "let h = std::env::" .. var .. ";\n")
    local why = ". A test reads nothing of the machine: take a folder from T.scratch or T.home(),"
      .. " or seal the command (the skills lua-testing and rust-testing, part Self-contained)"
    eq(
      table.concat(lint.check(root), "\n"),
      table.concat({
        "crates/x/tests/b.rs: 1 of `var(" .. '"HOME")`' .. why,
        "tests/a.lua: 1 of `/" .. "home/`" .. why,
        "tests/a.lua: 1 of `" .. home .. "`" .. why,
        "tests/a.lua: `" .. user .. "` reads the machine and has no place in tests/timing-allowed.txt",
      }, "\n"),
      "the problems"
    )
  end
)

test(
  "testlint: the wall clock in a product file outside the list fails, and so does the schedule clock in a budget reader",
  function()
    -- The names are cut in two, so that the check does not count this file.
    local now, real = "api." .. "now()", "api." .. "real_ms()"
    local root = T.scratch .. "/testlint-clocks"
    os.execute("mkdir -p '" .. root .. "/tests' '" .. root .. "/runtime/lua/paw'")
    T.write_file(root .. "/tests/timing-allowed.txt", "")
    T.write_file(root .. "/runtime/lua/paw/mouse.tl", "local t = " .. real .. "\nlocal u = " .. now .. "\n")
    T.write_file(root .. "/runtime/lua/paw/limit.tl", "local d = " .. now .. " + 5\nlocal e = " .. real .. "\n")
    T.write_file(root .. "/runtime/lua/paw/help.tl", "local d = " .. now .. "\nlocal e = " .. real .. "\n")
    eq(
      table.concat(lint.check(root), "\n"),
      table.concat({
        "runtime/lua/paw/limit.tl: 1 of `"
          .. now
          .. "` in a budget reader. A budget of work reads `"
          .. real
          .. "`:"
          .. " the schedule clock does not move in a test",
        "runtime/lua/paw/mouse.tl: 1 of `"
          .. real
          .. "`, the wall clock. A delay or a throttle reads `"
          .. now
          .. "`;"
          .. " a budget of work goes in the list `real_time` of tools/testlint.lua",
      }, "\n"),
      "the problems"
    )
  end
)

test("testlint: a quarantined Rust test and its line in the quarantine list go together", function()
  local root = T.scratch .. "/testlint-quarantine"
  os.execute("mkdir -p '" .. root .. "/tests' '" .. root .. "/crates/paw-core/tests'")
  local ignore = '#[ignore = "quarantine: the fix of the race"]'
  T.write_file(
    root .. "/crates/paw-core/tests/it.rs",
    "#[test]\n" .. ignore .. "\nfn a_listed_test() {}\n\n#[test]\n" .. ignore .. "\nfn a_test_with_no_line() {}\n"
  )
  T.write_file(
    root .. "/tests/quarantine.txt",
    "# a comment\na Lua test\tthe fix\npaw-core::it a_listed_test\tthe fix of the race\n"
      .. "paw-core::it model::a_test_with_no_ignore\tthe fix\n"
  )
  local problems = lint.check_quarantine(root)
  table.sort(problems)
  eq(problems, {
    "crates/paw-core/tests/it.rs: the quarantined test a_test_with_no_line has no line in tests/quarantine.txt"
      .. " (its binary id and name, a tab, the fix)",
    "tests/quarantine.txt: the Rust test model::a_test_with_no_ignore has no "
      .. '#[ignore = "quarantine: <the fix>"]: give it one, or remove its line',
  }, "the problems")
end)
