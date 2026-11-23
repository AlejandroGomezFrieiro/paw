-- Tests of the schedule clock that the suite runs on (`paw --clock manual`)
-- and of the helpers that move it: T.settle, T.advance, T.advance_until and
-- T.until_ (docs/how-to/run-the-tests.md). Loaded by tests/suite.lua with
-- its helpers.
local T = ...
local test, eq, fails = T.test, T.eq, T.fails
local api = paw.api

local function manual()
  T.fresh()
  if not T.manual then return "the schedule clock is the wall clock" end
end

--- A timer of the test, stopped when the test ends.
local function timer(fn, ms)
  local id = paw.defer(fn, ms)
  T.after(function() paw.cancel(id) end)
end

test("T.until_ on a condition that never holds fails with 'nothing is left to do', before a later timer", function()
  local skip = manual()
  if skip then return skip end
  local fired = false
  -- T.until_ plays about two seconds of blocks before it gives up: the
  -- timer is due after them.
  timer(function() fired = true end, 10000)
  fails(function()
    T.until_(function() return false end, "the thing")
  end, "nothing is left to do, and the thing is false", "a wait for a state that never comes")
  eq(fired, false, "the wait does not go on to a timer")
  T.advance_until(function() return fired end, "the timer", 10000)
end)

test("T.advance fires each timer at its own time, in order, and paw.api.pending names the next one", function()
  local skip = manual()
  if skip then return skip end
  local fired = {}
  T.settle()
  timer(function() fired[#fired + 1] = "30" end, 30)
  timer(function() fired[#fired + 1] = "10" end, 10)
  local pending = api.pending()
  eq(pending.timers_due, 0, "nothing is due")
  eq(pending.next_ms <= 10, true, "a timer is due in 10 ms at most: " .. pending.next_ms)
  T.advance(9)
  eq(table.concat(fired, " "), "", "after 9 ms")
  T.advance(1)
  eq(table.concat(fired, " "), "10", "after 10 ms")
  T.advance(19)
  eq(table.concat(fired, " "), "10", "after 29 ms")
  T.advance(1)
  eq(table.concat(fired, " "), "10 30", "after 30 ms, in order")
end)

test("T.advance_until moves the clock to the timer that makes the state, and fails past its limit", function()
  local skip = manual()
  if skip then return skip end
  local done, later = false, false
  timer(function() done = true end, 250)
  timer(function() later = true end, 400)
  T.advance_until(function() return done end, "the timer", 1000)
  eq(later, false, "the clock stopped at the timer")
  -- The second timer is 150 ms away: past a limit of 100 ms.
  fails(function()
    T.advance_until(function() return later end, "the second timer", 100)
  end, "the second timer is false after 100 ms", "a state that comes after the limit")
  T.advance(49)
  eq(later, false, "149 ms after the first timer")
  T.advance(1)
  eq(later, true, "150 ms after the first timer")
end)

test("a job that looks again at no delay does not stop the clock before a later timer", function()
  local skip = manual()
  if skip then return skip end
  local ready, polls = false, 0
  local poll
  poll = function()
    polls = polls + 1
    if not ready then timer(poll, 0) end
  end
  timer(poll, 0)
  timer(function() ready = true end, 30)
  T.advance(50)
  eq(ready, true, "the timer 30 ms on fired")
  eq(polls > 1, true, "and the job looked again until then")
end)
