-- The time limit and the budget of Lua callbacks, which are on the wall
-- clock: each test here is live (it spins in Lua to pass a limit), and runs
-- on the wall clock (tests/suite.lua, "Time in the tests"). The other tests
-- of the limits are in tests/flow.lua.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

local function has(text, part, what)
  if not text:find(part, 1, true) then error(string.format("%s: %q is not in\n%s", what or "text", part, text), 2) end
end

local function start()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
end

--- Read the messages, as a person would, so that the key line stops
--- mentioning the errors these tests make.
local function read_errors()
  paw.cmd("messages")
  paw.ui.close()
end

-- A time limit on runaway Lua ---------------------------------------------------

test("time spent waiting in the kernel does not count against a callback", function()
  start()
  local limit = paw.opt.lua_limit
  paw.opt.lua_limit = 150
  local before, reached = #paw.ui.messages, false
  paw.limit.guard("test", function()
    paw.api.wait(400)
    -- Enough work afterwards for the clock to be looked at again.
    local x = 0
    for i = 1, 400000 do
      x = x + i % 3
    end
    paw.limit.unhurried(function()
      local till = paw.api.now() + 300
      while paw.api.now() < till do
      end
    end)
    for i = 1, 400000 do
      x = x + i % 3
    end
    reached = true
  end)
  paw.opt.lua_limit = limit
  eq(reached, true, "the callback ran to its end")
  for i = before + 1, #paw.ui.messages do
    eq(paw.ui.messages[i].level ~= "error", true, "no error")
  end
end, { live = "it spins in Lua to pass the time limit, which is on the wall clock" })

test(":lua asked for by hand gets far longer than a callback", function()
  start()
  local limit = paw.opt.lua_limit
  paw.opt.lua_limit = 100
  local before = #paw.ui.messages
  paw.limit.guard(
    "test",
    paw.commands.run,
    "lua",
    { "(function() local t = paw.api.now() + 300 while paw.api.now() < t do end return 'done' end)()" }
  )
  paw.opt.lua_limit = limit
  eq(paw.ui.messages[#paw.ui.messages].text, '"done"', "it ran to the end")
  for i = before + 1, #paw.ui.messages do
    eq(paw.ui.messages[i].level ~= "error", true, "no error")
  end
end, { live = "it spins in Lua to pass the time limit, which is on the wall clock" })

-- A budget for each callback, and long work in slices ---------------------------

--- Wait `ms` milliseconds without returning, as slow code does.
local function busy(ms)
  local till = api.now() + ms
  while api.now() < till do
  end
end

--- The `slow:` warnings written since message `from` that match `part`
--- (on a loaded machine, other callbacks can be slow too).
local function slow_since(from, part)
  local out = {}
  for i = from + 1, #paw.ui.messages do
    local m = paw.ui.messages[i]
    if m.text:match("^slow: ") and m.text:find(part) then out[#out + 1] = m end
  end
  return out
end

local function with_budget(ms)
  local was = paw.opt.budget_ms
  paw.opt.budget_ms = ms
  T.after(function() paw.opt.budget_ms = was end)
end

test("a key over paw.opt.budget_ms is named once in :messages, with its time", function()
  start()
  with_budget(5)
  paw.keymap.set("gY", function() busy(20) end, { view = "arrange", desc = "zz slow key" })
  paw.keymap.set("gV", function() busy(1) end, { view = "arrange", desc = "zz quick key" })
  T.after(function()
    paw.keymap.del("gY", { view = "arrange" })
    paw.keymap.del("gV", { view = "arrange" })
  end)
  local before = #paw.ui.messages
  paw.keymap.feed("gY")
  local slow = slow_since(before, "zz ")
  eq(#slow, 1, "one warning")
  eq(slow[1].level, "warn", "a warning")
  has(slow[1].text, "slow: the key gY (zz slow key) ", "it names the keys")
  local ms = tonumber(slow[1].text:match(" (%d+) ms %(budget 5 ms%)$"))
  eq(ms ~= nil and ms >= 20, true, "it gives the time and the budget: " .. slow[1].text)
  paw.keymap.feed("gY")
  paw.keymap.feed("gV")
  eq(#slow_since(before, "zz "), 1, "a second press and a quick key write nothing more")
  read_errors()
end, { live = "it spins in Lua to pass the time limit, which is on the wall clock" })

test("the budget names a slow timer and a slow event handler", function()
  start()
  with_budget(5)
  local id = paw.on("zz.slow_event", function() busy(20) end)
  T.after(function() paw.off(id) end)
  local before = #paw.ui.messages
  paw.emit("zz.slow_event", {})
  paw.defer(function() busy(20) end)
  T.settle()
  local handler, timer = slow_since(before, "zz.slow_event"), slow_since(before, "live_limits.lua:")
  eq(#handler, 1, "one warning for the event handler")
  has(handler[1].text, "slow: a handler of `zz.slow_event` ", "it names the event")
  eq(#timer, 1, "one warning for the timer")
  has(timer[1].text, "slow: a timer (tests/live_limits.lua:", "named by where its function is")
  eq(#slow_since(before, "^slow: a timer %d"), 0, "and none for the call around it")
  read_errors()
end, { live = "it spins in Lua to pass the time limit, which is on the wall clock" })

test("a long job runs in slices of at most its time, and a key comes in between", function()
  start()
  local spent, slices, given = 0, 0, {}
  local seen
  paw.keymap.set("gV", function() seen = paw.slices.job("zz job") end, { view = "arrange", desc = "zz look" })
  T.after(function() paw.keymap.del("gV", { view = "arrange" }) end)
  paw.slices("zz job", function(ms)
    given[#given + 1] = ms
    local t0 = api.now()
    busy(math.min(ms, 50 - spent))
    spent, slices = spent + (api.now() - t0), slices + 1
    return spent >= 50
  end)
  -- A key, as the kernel takes it between two timers.
  paw.defer(function() paw.keymap.feed("gV") end, 10)
  T.until_(function() return paw.slices.job("zz job") == nil end, "the job to end")
  for _, ms in ipairs(given) do
    eq(ms, 4, "each slice gets 4 ms")
  end
  eq(slices >= 10, true, "in slices: " .. slices)
  eq(seen ~= nil and seen.slices >= 1, true, "the key ran while the job ran, after a slice")
  for _, job in ipairs(paw.slices.running()) do
    eq(job.name ~= "zz job", true, "the job is gone when it is over")
  end
end, { live = "it spins in Lua to pass the time limit, which is on the wall clock" })
