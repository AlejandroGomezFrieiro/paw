-- The runner fails a test when an error reaches the message line and the
-- test did not expect it (tests/suite.lua, "The errors that reached the
-- message line"). `T.take_errors` gives what the runner reports at the end
-- of the test, and empties it: so these tests do not fail for it.
local T = ...
local test, eq = T.test, T.eq
local paw = require("paw")

-- The first line of each report. The lines after it are the whole error,
-- for the person who reads the failure.
local function first_lines(words)
  local out = {}
  for i, text in ipairs(words) do
    out[i] = text:match("^[^\n]*")
  end
  return table.concat(out, "\n")
end

test("an error of an event handler, a key or a timer fails the test unless the test expects it", function()
  T.start()
  local id = paw.on("zz_runner.test", function() error("zz handler broke", 0) end)
  T.after(function() paw.off(id) end)
  paw.keymap.set("gZ", function() error("zz key broke", 0) end, { view = "arrange", desc = "zz breaks" })
  T.after(function() paw.keymap.del("gZ", { view = "arrange" }) end)
  local function timer_breaks()
    local fired = false
    paw.defer(function()
      fired = true
      error("zz timer broke", 0)
    end)
    T.until_(function() return fired end, "the timer")
  end
  -- `want` is the start of the report.
  local cases = {
    {
      what = "a handler, not expected",
      run = function() paw.emit("zz_runner.test") end,
      want = "an error reached the message line: zz handler broke (from a handler of `zz_runner.test`)",
    },
    {
      what = "a key, not expected",
      run = function() T.keys("gZ") end,
      want = "an error reached the message line: zz key broke (from the key Z)",
    },
    { what = "a timer, not expected", run = timer_breaks, want = "an error reached the message line: zz timer broke" },
    { what = "expected", expect = "^zz handler broke$", run = function() paw.emit("zz_runner.test") end, want = "" },
    {
      what = "expected, and it did not come",
      expect = "zz never",
      run = function() end,
      want = 'no error matched the expected "zz never"',
    },
  }
  for _, case in ipairs(cases) do
    if case.expect then T.expect_error(case.expect) end
    case.run()
    local got = first_lines(T.take_errors())
    eq(got:sub(1, #case.want), case.want, case.what)
    eq(case.want == "", got == "", case.what .. ": nothing more")
  end
end)
