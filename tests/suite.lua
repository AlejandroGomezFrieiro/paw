-- The runner of the end-to-end tests, and their helpers: `paw --clean -l
-- tests/suite.lua [words]` runs every test (those whose name holds the
-- words). Each test drives the public `paw` module and checks what comes
-- out, including rendered audio.
local paw = require("paw")
-- The tests run only in the test environment of tests/tools/env.sh: a scratch
-- home and no plugin of the machine. A plugin of the machine can be a yabridge
-- bridge, which starts wine in the owner's prefix.
if os.getenv("PAW_TEST_ENV") ~= "1" then
  io.stderr:write("run the suite with tests/tools/suite.sh, or paw by hand with tests/tools/run.sh\n")
  os.exit(1)
end
local api = paw.api

-- The settings of the run --------------------------------------------------
--
-- tests/tools/suite.sh gives them in the environment:
--
--   PAW_TEST_OUT      the folder for the files of the run: times.txt (the
--                     wall time of each test file) and tap.lines (each
--                     result, for the TAP file of CI). Not set: no files.
--   PAW_TEST_REPEAT   run the tests N times, and stop after the first run
--                     that fails (to find a flaky test).
--   PAW_TEST_SHUFFLE  a seed: run the parts, and the tests in each part, in
--                     an order that the seed gives. The same seed gives the
--                     same order.
--   PAW_TEST_FIXTURE  a folder that holds test files in place of the
--                     checkout's (for the tests of this runner, in
--                     tests/runner.lua): its `*.lua` files, its own
--                     `quarantine.txt`, and `declarations.txt` in place of
--                     runtime/types/paw.lua.
local out_dir = os.getenv("PAW_TEST_OUT")
local rounds = tonumber(os.getenv("PAW_TEST_REPEAT") or "") or 1
local shuffle_seed = tonumber(os.getenv("PAW_TEST_SHUFFLE") or "")
local fixture = os.getenv("PAW_TEST_FIXTURE")

-- A fault of the run itself: the run stops before the first test, and
-- tests/tools/suite.sh shows the line that starts with FAIL.
local function refuse(name, why)
  print("FAIL  " .. name .. "\n      " .. why:gsub("\n", "\n      ") .. "\n\n1 failed")
  api.quit(1)
end

-- The binary against the runtime --------------------------------------------
--
-- With PAW_TEST_BIN, the binary can come from an older commit than the
-- runtime. Then the runtime calls functions of the kernel that the binary
-- does not have, and the tests fail with Lua errors far from the cause. The
-- stamp of the kernel API is the list of its functions in
-- runtime/types/paw.lua, which tools/apidoc.lua writes from a binary of the
-- same commit (and its check fails when the list is out of date). Each
-- function that the list declares must be in the binary. A newer binary
-- with more functions passes: the runtime does not call them.
local function missing_api(path)
  local file = io.open(path)
  if not file then return {} end
  local missing = {}
  for line in file:lines() do
    local name = line:match("^function paw%.api%.([%w_]+)%(")
    if name and api[name] == nil then missing[#missing + 1] = name end
  end
  file:close()
  return missing
end

local missing = missing_api(fixture and (fixture .. "/declarations.txt") or "runtime/types/paw.lua")
if #missing > 0 then
  refuse(
    "the binary has the kernel API of the runtime",
    string.format(
      "the paw binary is older than the runtime: it has no paw.api.%s%s.\n"
        .. "Build paw from this commit, or give PAW_TEST_BIN a binary of this commit.",
      table.concat(missing, ", paw.api.", 1, math.min(#missing, 5)),
      #missing > 5 and string.format(" (%d functions in all)", #missing) or ""
    )
  )
  return
end

-- The quarantine list ----------------------------------------------------------
--
-- tests/quarantine.txt: one line for each flaky test, the full name of the
-- test, a tab, and the fix that it waits for. A failure of a listed test is
-- reported as "quarantined" and does not fail the run. A listed test that
-- passes is reported too, so that its line can go when the fix is merged.
-- A Rust test in the list is ignored in its source; the Lua runner only
-- reads its line.
local quarantine_path = fixture and (fixture .. "/quarantine.txt") or "tests/quarantine.txt"

--- The quarantined tests, by name, with the fix that each waits for. Nil
--- and a message for a line with no fix.
local function read_quarantine(path)
  local file = io.open(path)
  if not file then return {} end
  local list, number = {}, 0
  for line in file:lines() do
    number = number + 1
    if line:match("%S") and not line:match("^#") then
      local name, fix = line:match("^([^\t]+)\t%s*(.-)%s*$")
      if not name or fix == "" then
        file:close()
        return nil, string.format("%s:%d has no tab and fix after the name of the test: %s", path, number, line)
      end
      list[name] = fix
    end
  end
  file:close()
  return list
end

local quarantined, quarantine_error = read_quarantine(quarantine_path)
if not quarantined then
  refuse("each quarantined test names its fix", quarantine_error)
  return
end

local tmp = os.getenv("TMPDIR") or "/tmp"
-- The shard's number keeps apart the folders of shards that start at once.
local scratch = tmp
  .. "/paw-test-"
  .. os.time()
  .. "-"
  .. math.floor(api.real_ms() * 1000)
  .. (os.getenv("PAW_TEST_SHARD") or ""):gsub("%D", "-")
os.execute("mkdir -p '" .. scratch .. "'")

-- Every file of the checkout outside `target/` and `.git`: at the end,
-- one that is new is a file a test left behind (a clip file named by a
-- clip's id was once written into the current directory).
local function checkout_files()
  -- .claude holds the worktrees of other checkouts, whose own suites write
  -- into them while this one runs.
  local out, pipe =
    {},
    io.popen(
      "find . -path ./target -prune -o -path ./.git -prune -o -path ./.claude -prune -o -type f -print 2>/dev/null"
    )
  if not pipe then return nil end
  for line in pipe:lines() do
    out[line] = true
  end
  pipe:close()
  return out
end
local files_before = checkout_files()

local tests, failed = {}, 0
-- The part and the file whose tests are being collected (see "Shards"
-- below): each test keeps them, so that the leak check names the part that
-- leaves state behind, and times.txt gives the time of each file.
local loading, loading_file
-- `opts.live` marks a test that needs real time, and says why: it runs in a
-- second paw on the wall clock (see "Time in the tests").
local function test(name, fn, opts)
  tests[#tests + 1] = { name = name, fn = fn, part = loading, file = loading_file, live = opts and opts.live }
end
-- Tests that run after all the others: those that load every extension.
local lasts = {}
local function last(name, fn, opts)
  lasts[#lasts + 1] =
    { name = name, fn = fn, part = loading, file = loading_file, live = opts and opts.live, last = true }
end
-- What a test asks to have undone when it ends, passed or failed, so that
-- a failure does not leave a setting behind for the tests after it.
local cleanups = {}
local function after(fn) cleanups[#cleanups + 1] = fn end

-- The errors that reached the message line --------------------------------
--
-- paw.try reports an error as a message and does not raise it: an event
-- handler, a timer, a job and each key go through it. So the runner wraps
-- paw.try and keeps each error that it reports while a test runs. A test
-- fails when one of them is not an error that it expects
-- (`T.expect_error`), and when an error that it expects does not come.
-- The modules look up `paw.try` at each call, so the wrapper sees all of them.
local reported, expected = {}, {}
local paw_try = paw.try

-- Where an error that paw.try caught comes from, in words.
local function origin(fn, ...)
  if fn == paw.limit.named then return (...) end -- "a handler of `render.before`", "the job x"
  if fn == paw.keymap.dispatch then return "the key " .. tostring((...)) end
  if type(fn) ~= "function" then return tostring(fn) end
  local info = debug.getinfo(fn, "S")
  return info.short_src .. ":" .. info.linedefined
end

function paw.try(fn, ...)
  local result = { paw_try(fn, ...) }
  if not result[1] then
    -- The text as the message line shows it: paw.try has just said it.
    local said = paw.ui.messages[#paw.ui.messages]
    reported[#reported + 1] =
      { text = said and said.text or tostring(result[2]), from = origin(fn, ...), whole = tostring(result[2]) }
  end
  return unpack(result, 1, table.maxn(result))
end

--- Say that the test gives an error that reaches the message line, and
--- that matches `pattern` (a Lua pattern). It can come any number of
--- times; the test fails if it does not come at all.
local function expect_error(pattern) expected[#expected + 1] = { pattern = pattern, seen = false } end

-- The errors of the test that it did not expect, and the expected errors
-- that did not come, in words. Empties both lists for the next test.
local function unexpected_errors()
  local words = {}
  for _, r in ipairs(reported) do
    local known = false
    for _, e in ipairs(expected) do
      if r.text:find(e.pattern) then
        e.seen, known = true, true
      end
    end
    if not known then
      words[#words + 1] = "an error reached the message line: "
        .. r.text
        .. " (from "
        .. r.from
        .. ")\n  "
        .. r.whole:gsub("\n", "\n  ")
    end
  end
  for _, e in ipairs(expected) do
    if not e.seen then words[#words + 1] = "no error matched the expected " .. string.format("%q", e.pattern) end
  end
  reported, expected = {}, {}
  return words
end

-- Two tables are equal when they hold the same values: paw.inspect sorts
-- the keys, so equal tables give the same text.
local function same(got, want)
  if type(got) == "table" and type(want) == "table" then return paw.inspect(got) == paw.inspect(want) end
  return got == want
end

local function eq(got, want, what)
  if not same(got, want) then
    error(string.format("%s: got %s, want %s", what or "value", paw.inspect(got), paw.inspect(want)), 2)
  end
end

local function near(got, want, tolerance, what)
  if math.abs(got - want) > tolerance then
    error(string.format("%s: got %s, want %s ± %s", what or "value", got, want, tolerance), 2)
  end
end

local function fails(fn, pattern, what)
  local ok, err = pcall(fn)
  if ok then error((what or "call") .. " should have failed", 2) end
  if pattern and not tostring(err):find(pattern) then
    error(string.format("%s: error %q does not mention %q", what or "call", tostring(err), pattern), 2)
  end
end

-- Time in the tests ------------------------------------------------------------
--
-- The suite runs paw with `--clock manual` (tests/tools/suite.sh): schedule
-- time (`api.now()`, the timers, the settle delays) moves only when a test
-- lets it pass with `T.advance`, so a test steps each timer in its order
-- and does not race it. The manual clock reads 0 until something waits,
-- so the runner knows it at its start. The audio engine runs on the
-- stepped backend then: it plays a block only when the clock gets to its
-- end, so the sound, the meters and the playhead are one time with the
-- clock, and a test that reads a meter after `T.next_block(n)` reads the
-- same value in each run. Work on other threads and in other processes
-- (bakes, plugin loads, renders) still takes wall time: a wait for it is
-- a wait for an event, and the one limit of wall time is the stall guard.
-- A test that needs real time is live (`T.live`), and runs in a second paw
-- on the wall clock and the null backend.
local MANUAL = api.now() == 0
-- The stall guard: the wall time that one wait may take. It shows a fault,
-- not a speed.
local STALL_MS = 30000

-- The engine plays on the stepped backend from the start: each later start
-- on the null backend is stepped too. (The check of the binary above makes
-- sure that the kernel has it: `api.wait_blocks`.)
if MANUAL then api.engine_restart({ backend = "step" }) end

--- Whether the engine plays only as the clock moves. A test can start it
--- on another backend (the `test` device), which plays on the wall clock.
local function stepped() return MANUAL and api.engine_get().stepped == true end

-- Work that a turn or another thread does now: a settle waits for it. The
-- job `collector` (paw.collector) is idle work that each turn can start
-- again: its timer is not work left.
local function working(p)
  local idle = paw.slices.job("collector") and 1 or 0
  return math.max(0, p.timers_due - idle) + p.bakes_running + p.hashing + p.plugin_loads + p.renders + p.midi > 0
end

--- Whether the engine plays: the song plays or records, a take is being
--- closed, or a sound file plays. It changes the state as it plays: on the
--- stepped backend as the clock moves, else on the wall clock by itself.
local function engine_plays()
  local t = api.transport_get()
  local preview = api.preview_get()
  return t.playing
    or t.recording
    or (t.closing or 0) > 0
    or (preview ~= nil and (preview.state == "playing" or preview.state == "loading"))
end

-- Something that goes on and can change the state while the test waits:
-- the engine that plays, and helper processes that still write.
local function busy(p) return p.helpers > 0 or engine_plays() end

local function stalled(what, level)
  error(string.format("stalled: %s after %d ms of wall time", what, STALL_MS), level + 1)
end

-- The turns in a row with only timers due, after which they are a poll: a
-- job that looks again and again, at no delay, for a state that a timer
-- later on makes. A poll is not work left.
local POLL_TURNS = 1000

-- The schedule time that one test may take on the manual clock, ten
-- minutes: each wait of `T` has its own limit, and this one stops a test
-- that waits again and again without end. It is measured on the clock,
-- not on the wall.
local TEST_CLOCK_MS = 600000
-- The clock when the test that runs began (nil between tests).
local test_began

--- Turn the loop until nothing is ready and no work is in flight: the
--- timers that are due fired, and the bakes, plugin loads and renders
--- ended. No schedule time passes. Gives what `api.pending()` gives then.
local function settle()
  if MANUAL and test_began and api.now() - test_began > TEST_CLOCK_MS then
    error(string.format("the test ran more than %d ms of the clock", TEST_CLOCK_MS), 2)
  end
  local guard = api.real_ms() + STALL_MS
  local only_timers = 0
  while true do
    api.step()
    local p = api.pending()
    if not working(p) then return p end
    if p.bakes_running + p.hashing + p.plugin_loads + p.renders + p.midi == 0 then
      only_timers = only_timers + 1
      if only_timers >= POLL_TURNS then return p end
    else
      only_timers = 0
    end
    if api.real_ms() > guard then stalled("the work in flight (" .. paw.inspect(p) .. ")", 2) end
    -- Another thread works: let it.
    if p.timers_due == 0 then api.sleep(1) end
  end
end

--- The time of one audio block in whole milliseconds, rounded up: the
--- clock moves in whole milliseconds (`api.wait`).
local function block_ms()
  local e = api.engine_get()
  return math.ceil((e.buffer_size or 512) * 1000 / (e.sample_rate or 48000))
end

--- Let a backend that plays on the wall clock run `n` blocks, as far as
--- it runs: an engine with no device, for example one that was unplugged,
--- runs none. It waits at most four times the time of the blocks, at least
--- 250 ms, and does not fail. True when the engine ran them. After an
--- engine ran none, it looks only briefly (50 ms) until the engine runs a
--- block again: a restarted engine counts its blocks from the start.
local stopped_at
local function catch_up_on_the_wall(n)
  local start = api.blocks()
  if not start then return false end
  local full = api.real_ms() + math.max(250, 4 * n * block_ms())
  local guard = start == stopped_at and api.real_ms() + 50 or full
  while (api.blocks() or 0) < start + n + 1 do
    -- The engine runs: give it all of its time.
    if (api.blocks() or 0) ~= start then guard = full end
    if api.real_ms() > guard then
      stopped_at = api.blocks()
      return false
    end
    api.sleep(1)
  end
  stopped_at = nil
  return true
end

--- Let `ms` milliseconds of schedule time pass: each timer and settle
--- delay that is due in that time fires in its order, the stepped engine
--- plays the blocks of that time, and then the kernel settles. An engine
--- on the wall clock first runs one block, or the blocks of `ms` while it
--- plays, so the clock does not go past the sound. On the wall clock (a
--- live test) it waits `ms`.
local function advance(ms)
  if MANUAL and ms > 0 and not stepped() then
    catch_up_on_the_wall(engine_plays() and math.ceil(ms / block_ms()) or 1)
  end
  api.wait(ms)
  if MANUAL then settle() end
end

-- In a test on the manual clock, `paw.wait(ms)` is `T.advance(ms)`: the
-- time passes at once, and the kernel settles after it.
if MANUAL then paw.wait = advance end

--- Let the engine play one block, and settle. On the stepped backend the
--- clock moves to the end of the block; else the clock moves by the time
--- of a block, as far as the engine catches up on the wall clock.
local function one_block()
  if stepped() then
    api.wait_blocks(1)
    settle()
  else
    advance(block_ms())
  end
end

--- Let the engine play `n` (1 if not given) whole blocks after this call,
--- so that what was sent to it before is in effect: a parameter, a note,
--- a change to a track. Changes not yet sent are sent first. With
--- `device`, count the blocks that this device ran: a device that sleeps
--- through silence does not count them. On the stepped backend it plays
--- exactly `n` blocks (and the clock moves by their time), or, with
--- `device`, as many as the device needs, up to the blocks of the stall
--- guard. An engine on the wall clock runs on its own: then it waits for
--- the blocks, and the stall guard is the limit.
local function next_block(n, device)
  n = n or 1
  paw.flush()
  local start = api.blocks(device)
  if start == nil then error("the engine has no device " .. tostring(device), 2) end
  if stepped() then
    if not device then
      api.wait_blocks(n)
      return
    end
    for _ = 1, math.ceil(STALL_MS / block_ms()) do
      if api.blocks(device) >= start + n then return end
      api.wait_blocks(1)
    end
    error(string.format("the device %s ran %d of %d blocks", device, api.blocks(device) - start, n), 2)
  end
  -- The block under way may have started before the change came: the
  -- next one to finish does not count.
  local want = start + n + 1
  local guard = api.real_ms() + STALL_MS
  while (api.blocks(device) or 0) < want do
    if api.real_ms() > guard then
      stalled(
        string.format(
          "the engine ran %d of %d blocks%s",
          (api.blocks(device) or 0) - start,
          want - start,
          device and (" of device " .. device) or ""
        ),
        2
      )
    end
    api.sleep(1)
  end
end

-- The audio blocks that the engine plays before a wait says that nothing is
-- left to do, about two seconds of sound: a change that it takes in, a
-- device that falls asleep or a meter that falls shows after some blocks.
local ENGINE_BLOCKS = 200

--- Settle, then let the engine play up to ENGINE_BLOCKS blocks, until
--- `cond()` holds. Gives the value of `cond()`, or false when nothing is
--- left to do and it is still false, or nil when something is still busy
--- (a helper process, or the engine that plays).
local function quiet(cond)
  for _ = 1, ENGINE_BLOCKS do
    local p = settle()
    local value = cond()
    if value then return value end
    if busy(p) then return nil end
    if stepped() then
      one_block()
    elseif not catch_up_on_the_wall(1) then
      -- An engine that runs no blocks changes nothing more.
      break
    end
  end
  local p = settle()
  local value = cond()
  if value then return value end
  if busy(p) then return nil end
  return false
end

--- Wait until `cond()` gives a value that is not false or nil, and give
--- that value. The kernel settles, and the engine plays block by block
--- while the condition waits for it (a meter, the playhead, a device that
--- sleeps): then the clock keeps step with the sound. When nothing is
--- left to do and `cond()` is still false, it fails: a timer that waits
--- for the clock is not work left (`T.advance_until` moves the clock to
--- it). While the song plays, it fails after 30 seconds of the song. A
--- live test waits on the wall clock for at most `ms` milliseconds (30
--- seconds if not given).
local function until_(cond, what, ms)
  what = what or "the condition"
  if not MANUAL then
    ms = ms or STALL_MS
    local deadline = api.now() + ms
    while true do
      local value = cond()
      if value then return value end
      if api.now() > deadline then error(string.format("waited %d ms in vain for %s", ms, what), 2) end
      paw.wait(5)
    end
  end
  local guard = api.real_ms() + STALL_MS
  local limit = api.now() + STALL_MS
  while true do
    local value = quiet(cond)
    if value then return value end
    if value == false then error("nothing is left to do, and " .. what .. " is false", 2) end
    if api.real_ms() > guard then stalled(what, 2) end
    if api.now() > limit then error(string.format("%s is false after %d ms of the song", what, STALL_MS), 2) end
    if engine_plays() then
      one_block()
    else
      api.sleep(1)
    end
  end
end

--- Wait until no meter of the engine shows a level: the master's and each
--- track's are under the meters' floor (-60 dB). The engine lets a meter
--- fall in its own blocks, which run on the wall clock, so the sound of a
--- test before can still fall when the next test draws a meter. Then put
--- out the peaks that the screen holds for two seconds of the clock, and
--- the clip lights.
local function until_meters_at_rest()
  local ids = api.track_list({ all = true })
  ids[#ids + 1] = 0
  until_(function()
    for _, id in ipairs(ids) do
      if math.max(api.track_meter(id)) >= 0.001 then return false end
    end
    return true
  end, "the meters of the engine at rest")
  for _, id in ipairs(ids) do
    paw.draw.clear_peak(id)
  end
end

--- Let schedule time pass, from one due timer or delay to the next, until
--- `cond()` gives a value that is not false or nil, and give that value.
--- With no timer due, or while a helper process or the engine that plays
--- is busy, the clock moves by one audio block at most: so a state that a
--- time, the meters or a helper makes comes too. Fails when `ms`
--- milliseconds of schedule time passed.
local function advance_until(cond, what, ms)
  what = what or "the condition"
  if not MANUAL then return until_(cond, what, ms) end
  local limit = api.now() + ms
  while true do
    local p = settle()
    local value = cond()
    if value then return value end
    local left = limit - api.now()
    if left <= 0 then error(string.format("%s is false after %g ms", what, ms), 2) end
    if busy(p) or not p.next_ms then
      one_block()
    else
      advance(math.min(math.max(1, math.ceil(p.next_ms)), left))
    end
  end
end

--- The level of the meter of `thing` (a track, or another thing with
--- `:meter()`) after the blocks that the engine played last: left and
--- right peaks, as linear gain. On the manual clock the engine must be on
--- the stepped backend, so that the level is the same in each run: play
--- with `T.next_block(n)`, `T.advance(ms)` or `T.until_beat`, then read it.
--- A live test reads it on the wall clock.
local function meter(thing)
  if MANUAL and not stepped() then
    error("a meter is read on the stepped backend (or in a live test), not on " .. api.engine_get().backend, 2)
  end
  return thing:meter()
end

--- The peak level of `track` once the engine ran one more block
--- (`next_block`): the left side, or the right with `side` 2. A test reads
--- a level only after a block, never after a time: in a wait,
--- `T.until_(function() return T.level(t) > 0.01 end, what)`.
local function level(track, side)
  next_block(1)
  return (select(side or 1, meter(track)))
end

--- Let the song play until the playhead, after it went round the loop
--- `rounds` times (0 if not given), is at `beat` or past it. A test that
--- plays or records waits for the playhead, not for a time: the clock
--- moves block by block with the sound. Fails after `ms` milliseconds of
--- the song (30 seconds if not given).
local function until_beat(beat, rounds, ms)
  local before, wraps = paw.transport.position, 0
  advance_until(function()
    local now = paw.transport.position
    if now < before then wraps = wraps + 1 end
    before = now
    return wraps >= (rounds or 0) and now >= beat
  end, string.format("the playhead at beat %g after %d times round the loop", beat, rounds or 0), ms or STALL_MS)
end

--- Run `fn`, and give for each device of `...` whether it made sound then:
--- true or false, in the same order. A device at rest sleeps through
--- silence (`paw.opt.device_sleep`) and wakes for a note or a sound. So
--- each device falls asleep first, `fn` runs, and after a few blocks the
--- devices that ran blocks of their own are the ones that sound. No meter
--- is read: a live meter depends on the blocks that ran in a time.
local function wakes(fn, ...)
  local devices = { ... }
  if not paw.opt.device_sleep then error("T.wakes needs paw.opt.device_sleep", 2) end
  local function ran()
    local counts = {}
    for i, device in ipairs(devices) do
      counts[i] = api.blocks(device.id)
    end
    return counts
  end
  until_(function()
    local before = ran()
    next_block(3)
    local after = ran()
    for i = 1, #devices do
      if after[i] ~= before[i] then return false end
    end
    return true
  end, "the devices to fall asleep")
  local before = ran()
  fn()
  next_block(3)
  local after, sounded = ran(), {}
  for i = 1, #devices do
    sounded[i] = after[i] > before[i]
  end
  return unpack(sounded, 1, #devices)
end

--- Wait until each take that stopped is clips in the project, and the
--- handlers of their events have run. A stop ends a take at once, and its
--- clips come when the engine has let go of it (`transport.recorded`).
local function until_recorded()
  until_(function() return (api.transport_get().closing or 0) == 0 end, "the takes that stopped to become clips")
  paw.flush()
end

--- Stop the song, and wait until the take that it ends is clips.
local function stop()
  paw.transport.stop()
  until_recorded()
end

local function fresh()
  -- Keys half typed, a selection, insert or command line mode, and the
  -- floats an earlier test left open would take this test's first keys.
  local K = paw.keymap
  if K.mode ~= "n" or K.visual or K.pending() ~= "" then K.feed("<Esc><Esc>") end
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.hover_close()
  paw.project.new()
  paw.transport.loop_enabled = false
  -- The windows and tabs an earlier test opened would share the screen
  -- with this one's: each test starts from the default start layout.
  local L = require("paw.layout")
  if #paw.ui.tabs > 1 or #L.windows(paw.ui.layout) ~= 1 or L.windows(paw.ui.layout)[1].view ~= "arrange" then
    L.restore({ { layout = L.default_tree() } })
  end
  -- A window narrowed to a group or a region shows the whole song again.
  for _, w in ipairs(L.windows(paw.ui.layout)) do
    if w.scope and paw.scope then paw.scope.restore(nil, w) end
  end
  -- The views that an earlier test popped out into windows of their own
  -- (a tuner, a meter) go back: the start layout has no such window.
  for _, w in ipairs(paw.canvas.windows()) do
    paw.canvas.close(w.name)
  end
  paw.ui.close()
  paw.ui.focus("arrange")
  -- `<C-w>p` goes to the window before: a new test has none.
  L.tab().prev = nil
  -- The quickfix lists of an earlier test address its project: a new
  -- project starts with none.
  local qf = paw.qf.stack()
  qf.lists, qf.at = {}, 0
  -- An error of an earlier test would stay named on the key line.
  require("paw.views.cmdline").read_errors()
  paw.flush()
end

--- `fresh()`, then `<Esc><Esc>` as a person types it in the arrange view:
--- what most tests that type keys start from.
local function start()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
end

--- The text of the screen, `w` columns by `h` rows (120 by 40 if not
--- given), one line for each row.
local function screen(w, h) return table.concat(api.ui_snapshot(w or 120, h or 40), "\n") end

--- What the float of `K` says (`paw.ui.hover`): its title, then its lines,
--- one a row. Empty when no hover is open.
local function hover_text()
  local hover = paw.ui.hovered
  if not hover then return "" end
  local out = { hover.title }
  for _, line in ipairs(hover.lines) do
    out[#out + 1] = line.text
  end
  return table.concat(out, "\n")
end

local renders = 0
local function render(opts)
  renders = renders + 1
  return paw.render(scratch .. "/render" .. renders .. ".wav", opts)
end

--- A track with a synth holding one note for `beats`.
local function tone(name, beats, pitch)
  local track = paw.add_track({ name = name })
  track:add_device("synth", { attack = 0.001, release = 0.01 })
  track:add_clip({ start = 0, length = beats, notes = { { pitch = pitch or "A3", start = 0, length = beats } } })
  return track
end

--- Peak of each channel of a WAV file written by `paw.render` at 16 bits,
--- optionally only between two times in seconds.
local function channel_peaks(info, from, to)
  local file = assert(io.open(info.path, "rb"))
  local data = file:read("*a")
  file:close()
  local at = data:find("data", 1, true) + 8
  local first = at + math.floor((from or 0) * info.sample_rate) * 4
  local last = to and math.min(#data - 1, at + math.floor(to * info.sample_rate) * 4) or #data - 1
  local peaks = { 0, 0 }
  local ch = 1
  for i = first, last - 1, 2 do
    local lo, hi = data:byte(i, i + 1)
    local v = lo + hi * 256
    if v >= 32768 then v = v - 65536 end
    peaks[ch] = math.max(peaks[ch], math.abs(v) / 32768)
    ch = 3 - ch
  end
  return peaks[1], peaks[2]
end

--- Frequency of the left channel of a WAV file written by `paw.render` at 16
--- bits, between two times in seconds, from its rising zero crossings.
local function frequency(info, from, to)
  local file = assert(io.open(info.path, "rb"))
  local data = file:read("*a")
  file:close()
  local at = data:find("data", 1, true) + 8
  local first = at + math.floor(from * info.sample_rate) * 4
  local last = math.min(#data - 1, at + math.floor(to * info.sample_rate) * 4)
  local rises, before = 0, 0
  for i = first, last - 1, 4 do
    local lo, hi = data:byte(i, i + 1)
    local v = lo + hi * 256
    if v >= 32768 then v = v - 65536 end
    if before < 0 and v >= 0 then rises = rises + 1 end
    before = v
  end
  return rises / (to - from)
end

local function read_file(path)
  local file = assert(io.open(path, "rb"))
  local data = file:read("*a")
  file:close()
  return data
end

local function write_file(path, data)
  local file = assert(io.open(path, "wb"))
  file:write(data)
  file:close()
end

-- Helpers of the modal editing tests ------------------------------------------

--- A track with a synth and three clips of four beats, a note on every beat.
local function three_clips()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  paw.ui.focus("arrange")
  local t = paw.add_track({ name = "T" })
  t:add_device("synth", { cutoff = 900 })
  for i, name in ipairs({ "a", "b", "c" }) do
    local notes = {}
    for beat = 0, 3 do
      notes[#notes + 1] = { pitch = 60 + beat, start = beat, length = 1 }
    end
    t:add_clip({ name = name, start = (i - 1) * 4, length = 4, notes = notes })
  end
  paw.cursor.set_track(t)
  paw.cursor.set_beat(0)
  paw.opt.grid, paw.opt.note_grid, paw.opt.ripple = 1, 0.25, false
  api.undo_checkpoint()
  return t
end

--- Where a track's clips are: "a@0+4 b@4+4".
local function layout(t)
  local out = {}
  for _, c in ipairs(api.clip_list(t.id)) do
    out[#out + 1] = string.format("%s@%g+%g%s", c.name, c.start, c.length, c.muted and "m" or "")
  end
  return table.concat(out, " ")
end

--- A clip's notes: "60@0+1 61@1+1".
local function melody(clip)
  local notes = clip:notes()
  table.sort(notes, function(a, b)
    if a.start ~= b.start then return a.start < b.start end
    return a.pitch < b.pitch
  end)
  for i, n in ipairs(notes) do
    notes[i] = string.format("%d@%g+%g", n.pitch, n.start, n.length)
  end
  return table.concat(notes, " ")
end

--- The notes of the piano roll as a window that paints them is sent them:
--- the scene's `note` roles, in drawing order.
local function roll_notes()
  api.scene_forget(0)
  api.scene_roles(0, { "note" })
  paw.ui.render_scene("pianoroll", 120, 40, { w = 8, h = 16 })
  local patch = api.json_decode(api.scene_end(0, "roll_notes"))
  api.scene_forget(0)
  local out = {}
  for _, n in ipairs(patch.set) do
    if n.role == "note" then out[#out + 1] = n end
  end
  return out
end

--- Type keys as one undo step, sent on to the engine.
local function keys(text)
  paw.keymap.feed(text)
  paw.flush()
  api.undo_checkpoint()
end

-- The home folder of a test. env.sh gives the run a scratch HOME, and a test
-- reads no home folder of its own accord: a test of `~` takes a folder of its
-- own with T.home, so that what it expects does not depend on the run.
local ffi = require("ffi")
pcall(ffi.cdef, "int setenv(const char *name, const char *value, int overwrite);")
local run_home, homes = os.getenv("HOME"), 0

--- Make HOME `dir` (else a new folder under T.scratch) until the test ends,
--- and give the folder.
local function home(dir)
  if not dir then
    homes = homes + 1
    dir = scratch .. "/home-" .. homes
  end
  os.execute("mkdir -p '" .. dir .. "'")
  ffi.C.setenv("HOME", dir, 1)
  after(function() ffi.C.setenv("HOME", run_home, 1) end)
  return dir
end

-- The tests ------------------------------------------------------------------
--
-- This file is the runner and the helpers; the tests are in files of their
-- own: those of the runtime in `tests/<area>.lua`, those of an extension
-- beside it in `extensions/<name>/tests.lua` and `tests_<part>.lua`. The
-- runner loads each such file, in the order of their names. Each is a
-- function of one table, the helpers above:
--
--   local T = ...
--   T.test("the widget counts", function() T.fresh() T.eq(1 + 1, 2, "sum") end)

--- Write a 16-bit WAV file from one list of samples per channel.
local function write_wav(path, left, right, rate)
  right, rate = right or left, rate or 48000
  local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
  local function u32(v) return u16(v % 65536) .. u16(math.floor(v / 65536)) end
  local data = {}
  for i = 1, #left do
    for _, v in ipairs({ left[i], right[i] }) do
      local s = math.floor(v * 32767 + 0.5)
      data[#data + 1] = u16(s < 0 and s + 65536 or s)
    end
  end
  data = table.concat(data)
  write_file(
    path,
    "RIFF"
      .. u32(36 + #data)
      .. "WAVEfmt "
      .. u32(16)
      .. u16(1)
      .. u16(2)
      .. u32(rate)
      .. u32(rate * 4)
      .. u16(4)
      .. u16(16)
      .. "data"
      .. u32(#data)
      .. data
  )
  return path
end

--- The left channel of a 16-bit render, as numbers from -1 to 1.
local function samples(info)
  local data = read_file(info.path)
  local at = data:find("data", 1, true) + 8
  local out = {}
  for i = at, #data - 3, 4 do
    local lo, hi = data:byte(i, i + 1)
    local v = lo + hi * 256
    out[#out + 1] = (v >= 32768 and v - 65536 or v) / 32768
  end
  return out
end

local T = {
  test = test,
  last = last,
  after = after,
  eq = eq,
  near = near,
  fails = fails,
  expect_error = expect_error,
  take_errors = unexpected_errors,
  fresh = fresh,
  start = start,
  screen = screen,
  hover_text = hover_text,
  render = render,
  tone = tone,
  until_ = until_,
  settle = settle,
  advance = advance,
  advance_until = advance_until,
  until_meters_at_rest = until_meters_at_rest,
  manual = MANUAL,
  next_block = next_block,
  stepped = stepped,
  meter = meter,
  level = level,
  until_beat = until_beat,
  wakes = wakes,
  until_recorded = until_recorded,
  stop = stop,
  scratch = scratch,
  home = home,
  read_file = read_file,
  write_wav = write_wav,
  samples = samples,
  write_file = write_file,
  frequency = frequency,
  channel_peaks = channel_peaks,
  three_clips = three_clips,
  layout = layout,
  melody = melody,
  keys = keys,
  roll_notes = roll_notes,
}
-- T.expect_screen and the check of unused golden files (tests/tools/golden.lua).
local golden_unused = dofile("tests/tools/golden.lua")(T)

-- Text fixtures ------------------------------------------------------------------
--
-- `T.check_keys(fixture, keys, expected, what)` makes the project of
-- `fixture` after `T.start()`, types `keys` with `T.keys`, and compares the
-- project with `expected`. A failure prints the project as a fixture, ready
-- to paste. `T.fixture(text)` only makes the project (and gives its tracks
-- by name), and `T.fixture_text()` gives the project as a fixture.
-- tests/tools/fixture.lua holds them.
--
-- A fixture is a small project in a Lua string, one item on each line.
-- The indent is for the eye; `--` starts a comment:
--
--   track Lead            -- a track (with a synth), named Lead
--     clip a 0+4          -- a MIDI clip named a, at beat 0, 4 beats long
--       60 0+0.5          -- a note: pitch 60, at beat 0 of the clip, half a beat
--       64 0.5+0.5 *      -- `*`: the note is chosen (selected)
--       cursor 64@0.5     -- the piano roll is open on this clip, with its
--                         -- cursor at pitch 64, beat 0.5 of the roll
--     cursor @2           -- or: the arrange view, its cursor on this track at beat 2
--   mode x v              -- the mode, when it is not normal (expected side only)
--
-- The project that a check prints has its clips and notes in the order they
-- start (the lower pitch first), the cursor of the view that has the focus,
-- and `*` on the notes that the pointer or a selection of visual mode chose.
dofile("tests/tools/fixture.lua")(T)
local files = {}
local function lua_files(dir, pattern)
  local found = {}
  for _, entry in ipairs(api.read_dir(dir)) do
    if not entry.is_dir and entry.name:match(pattern) and entry.name ~= "suite.lua" then
      found[#found + 1] = dir .. "/" .. entry.name
    end
  end
  table.sort(found)
  for _, path in ipairs(found) do
    files[#files + 1] = path
  end
end
if fixture then
  lua_files(fixture, "%.lua$")
else
  lua_files("tests", "%.lua$")
  local extensions = {}
  for _, entry in ipairs(api.read_dir("extensions")) do
    if entry.is_dir then extensions[#extensions + 1] = entry.name end
  end
  table.sort(extensions)
  for _, name in ipairs(extensions) do
    lua_files("extensions/" .. name, "^tests[%w_]*%.lua$")
  end
end
-- A part is a file of tests/, or all the test files of one extension: a
-- file of an extension can use what an earlier file of it set up
-- (tests_tone3000_auth.lua). The leak check runs after each part, and a
-- shard runs whole parts.
local function part_of(path) return path:match("^(extensions/[^/]+/)") or path end
-- Shards: `suite.sh -j N` starts N paw processes, and gives process K
-- (PAW_TEST_SHARD=K/N) every Nth part from the Kth.
local shard, shards = (os.getenv("PAW_TEST_SHARD") or ""):match("^(%d+)/(%d+)$")
shard, shards = tonumber(shard), tonumber(shards)
local parts, number = 0, {}
for _, path in ipairs(files) do
  local part = part_of(path)
  if not number[part] then
    parts = parts + 1
    number[part] = parts
  end
  if not shards or (number[part] - 1) % shards == shard - 1 then
    loading, loading_file = part, path
    assert(loadfile(path))(T)
  end
end
loading, loading_file = nil, nil
for _, t in ipairs(lasts) do
  tests[#tests + 1] = t
end

-- The leak check ---------------------------------------------------------------
--
-- After the tests of a part ran, the runner compares what a test can leave
-- behind with how it was at the start of the run: the event handlers,
-- timers and key mappings that the code of a test file made, and the loaded
-- extensions. The runner puts each of them back, so that the next part
-- starts as it does in the full suite, whatever ran before it. A handler,
-- timer or key mapping of test code that is still there, and an extension
-- that the runner cannot unload, fail "<part> leaves no state behind".
-- The runner also compares the state of the kernel that no registry holds
-- (`kernel` below). Any change of it is a leak, whatever code made it, and
-- the message names the first test that left it.
-- `tests/leaks-allowed.txt` lists the leaks that are known, one
-- "<part> <kind>" on each line: the list only gets shorter.

local kinds = { "hooks", "timers", "keys", "extensions", "engine", "midi", "step", "held", "plugins" }
local watched = { hooks = true, timers = true, keys = true }

-- Whether a function's source is a test file.
local function of_tests(fn)
  if type(fn) ~= "function" then return false end
  local source = debug.getinfo(fn, "S").source
  return source:match("^@tests/") ~= nil or source:match("^@extensions/[^/]+/tests[%w_]*%.lua$") ~= nil
end

-- Whether an entry of a registry is a test's: a function of a test file,
-- or a table with one among its fields (a key mapping, an event handler).
local function made_by_tests(value)
  if of_tests(value) then return true end
  if type(value) ~= "table" then return false end
  for _, v in pairs(value) do
    if of_tests(v) then return true end
  end
  return false
end

local registries = {}
for _, reg in ipairs(paw.ext.registries) do
  if watched[reg.kind] then registries[reg.kind] = reg end
end

local plugin_formats = { clap = true, lv2 = true, vst3 = true }

-- The kinds of plugin devices, as a set.
local function plugin_kinds()
  local out = {}
  for _, info in ipairs(api.device_types()) do
    if plugin_formats[info.format] then out[info.kind] = true end
  end
  return out
end

-- State of the kernel that a test can change with the API, outside the
-- registries. `read` gives a label in words, which the check compares, and
-- the value that `put` takes to put it back. `put` runs in the order of the
-- list: an engine restart also empties the MIDI test ports. A state with
-- `each_part` is read only at the end of each part, because the read is
-- slow: then the message names no test.
local kernel = {
  {
    -- The audio backend and its settings (`api.engine_restart`).
    kind = "engine",
    read = function()
      local e = api.engine_get()
      local label = string.format("%s %g Hz %d frames", e.backend, e.sample_rate, e.buffer_size)
      return label .. (e.midi and " with MIDI" or ""), e
    end,
    put = function(e)
      api.engine_restart({
        backend = e.backend,
        sample_rate = e.sample_rate,
        buffer_size = e.buffer_size,
        midi = e.midi,
      })
    end,
  },
  {
    -- The MIDI inputs: the test ports on the null backend
    -- (`api.midi_test_ports`), and the ports of the program's own
    -- (`paw.midi.open_port`), which are marked "own".
    kind = "midi",
    read = function()
      local names, tests, own = {}, {}, {}
      for _, port in ipairs(api.midi_inputs()) do
        if port.own then
          own[port.name] = true
          names[#names + 1] = port.name .. " (own)"
        else
          tests[#tests + 1] = port.name
          names[#names + 1] = port.name
        end
      end
      return "ports {" .. table.concat(names, ", ") .. "}", { tests = tests, own = own }
    end,
    put = function(ports)
      api.midi_test_ports(ports.tests)
      for _, port in ipairs(api.midi_inputs()) do
        if port.own and not ports.own[port.name] then api.midi_close_port(port.name) end
      end
    end,
  },
  {
    -- The step input controls that Lua bound and no file saved.
    kind = "step",
    read = function()
      local sources = {}
      for _, b in ipairs(paw.step.bindings()) do
        if not b.saved then sources[#sources + 1] = paw.step.source_text(b.source) end
      end
      table.sort(sources)
      return "controls {" .. table.concat(sources, ", ") .. "}", sources
    end,
    put = function(sources)
      local keep = {}
      for _, text in ipairs(sources) do
        keep[text] = true
      end
      for _, b in ipairs(paw.step.bindings()) do
        if not b.saved and not keep[paw.step.source_text(b.source)] then paw.step.unbind(b.source) end
      end
    end,
  },
  {
    -- The tracks that the engine plays from a file (`api.engine_hold`).
    kind = "held",
    read = function()
      local ids = api.engine_held()
      return "tracks {" .. table.concat(ids, ", ") .. "}", ids
    end,
    put = function(ids)
      local keep = {}
      for _, id in ipairs(ids) do
        keep[id] = true
      end
      for _, id in ipairs(api.engine_held()) do
        if not keep[id] then pcall(api.engine_hold, id, nil) end
      end
    end,
  },
  {
    -- The plugin folders that Lua added (`api.plugins_add_dir`) and the
    -- plugin kinds. The list of all kinds is slow with many plugins.
    kind = "plugins",
    each_part = true,
    read = function()
      local dirs = api.plugins_dirs()
      if not dirs then return "no plugins", nil end
      local kinds, count = plugin_kinds(), 0
      for _ in pairs(kinds) do
        count = count + 1
      end
      return string.format("%d kinds, %d folders", count, #dirs.clap), { kinds = kinds, folders = dirs.clap }
    end,
    put = function(was)
      if not was then return end
      local known = {}
      for _, dir in ipairs(was.folders) do
        known[dir] = true
      end
      for _, dir in ipairs(api.plugins_dirs().clap) do
        if not known[dir] then
          paw.plugins.remove_dir(dir)
          api.plugins_remove_dir(dir, {})
        end
      end
      local added = {}
      for kind in pairs(plugin_kinds()) do
        if not was.kinds[kind] then added[#added + 1] = kind end
      end
      -- No folder holds them: only the kinds go.
      if #added > 0 then api.plugins_remove_dir("", added) end
    end,
  },
}

-- The entries of the watched registries, by kind and key, the loaded
-- extensions, and the state of the kernel, by kind.
local function fingerprint()
  local out = { extensions = {}, kernel = {} }
  for name in pairs(paw.ext.loaded) do
    out.extensions[name] = true
  end
  for kind, reg in pairs(registries) do
    out[kind] = reg.snapshot()
  end
  for _, state in ipairs(kernel) do
    local label, value = state.read()
    out.kernel[state.kind] = { label = label, value = value }
  end
  return out
end

-- What the tests changed since `base`, by kind, in words.
local function differences(base, now)
  local out = {}
  for kind, reg in pairs(registries) do
    local words = {}
    local function label(key, value) return reg.label and reg.label(key, value) or tostring(key) end
    for key, value in pairs(now[kind]) do
      if value ~= base[kind][key] and made_by_tests(value) then
        words[#words + 1] = (base[kind][key] and "~" or "+") .. label(key, value)
      end
    end
    for key, value in pairs(base[kind]) do
      if now[kind][key] == nil and made_by_tests(value) then words[#words + 1] = "-" .. label(key, value) end
    end
    if #words > 0 then
      table.sort(words)
      if #words > 6 then words = { table.concat(words, ", ", 1, 6) .. " and " .. (#words - 6) .. " more" } end
      out[kind] = table.concat(words, ", ")
    end
  end
  local changed = {}
  for name in pairs(now.extensions) do
    if not base.extensions[name] then changed[#changed + 1] = "+" .. name end
  end
  for name in pairs(base.extensions) do
    if not now.extensions[name] then changed[#changed + 1] = "-" .. name end
  end
  table.sort(changed)
  if #changed > 0 then out.extensions = table.concat(changed, ", ") end
  for _, state in ipairs(kernel) do
    local was, is = base.kernel[state.kind].label, now.kernel[state.kind].label
    if was ~= is then out[state.kind] = was .. " -> " .. is end
  end
  return out
end

-- Put back what the tests changed since `base`: the entries that test code
-- made, the extensions (those loaded since are unloaded), and the state of
-- the kernel.
local function reset(base, now)
  for _, state in ipairs(kernel) do
    if base.kernel[state.kind].label ~= state.read() then pcall(state.put, base.kernel[state.kind].value) end
  end
  for kind, reg in pairs(registries) do
    for key, value in pairs(now[kind]) do
      if value ~= base[kind][key] and made_by_tests(value) then pcall(reg.put, key, base[kind][key]) end
    end
  end
  -- An extension that another requires goes after it.
  local left = true
  while left do
    left = false
    for name in pairs(paw.ext.loaded) do
      if not base.extensions[name] and pcall(paw.ext.unload, name, { force = true }) and not paw.ext.loaded[name] then
        left = true
      end
    end
  end
end

local allowed, allowed_path = {}, "tests/leaks-allowed.txt"
do
  local file = io.open(allowed_path)
  if file then
    for line in file:lines() do
      local path, kind = line:match("^([^#%s]%S*)%s+(%S+)")
      if path then allowed[path .. " " .. kind] = true end
    end
    file:close()
  end
end

-- Run ------------------------------------------------------------------------

local only = ...
-- The live pass (PAW_TEST_LIVE=1, on the wall clock) runs the live tests
-- only. The pass on the manual clock runs the others.
local live_pass = os.getenv("PAW_TEST_LIVE") == "1"
if live_pass and MANUAL then
  error("PAW_TEST_LIVE=1 runs the live tests on the wall clock: start paw without --clock manual")
end
local function in_pass(t)
  if live_pass then return t.live ~= nil end
  return not (MANUAL and t.live)
end
local selected, whole = {}, {}
for _, t in ipairs(tests) do
  if in_pass(t) and (not only or t.name:find(only, 1, true)) then
    selected[#selected + 1] = t
    whole[t.part] = (whole[t.part] or 0) + 1
  end
end

-- The order of a shuffled run. The parts move as wholes, so that the leak
-- check after each part stays true, and the tests of each part move inside
-- it. The tests of `T.last` stay after all the others. The random numbers
-- come from the seed only (the "minimal standard" generator of Park and
-- Miller, exact in the doubles of LuaJIT), so a seed gives the same order
-- with each binary.
local function shuffled(list, seed)
  local state = seed % 2147483646 + 1
  local function below(n)
    state = state * 16807 % 2147483647
    return state % n + 1
  end
  local groups, group_of, lasts_run = {}, {}, {}
  for _, t in ipairs(list) do
    if t.last then
      lasts_run[#lasts_run + 1] = t
    else
      if not group_of[t.part] then
        group_of[t.part] = {}
        groups[#groups + 1] = group_of[t.part]
      end
      table.insert(group_of[t.part], t)
    end
  end
  local function shuffle(items)
    for i = #items, 2, -1 do
      local j = below(i)
      items[i], items[j] = items[j], items[i]
    end
  end
  shuffle(groups)
  local out = {}
  for _, group in ipairs(groups) do
    shuffle(group)
    for _, t in ipairs(group) do
      out[#out + 1] = t
    end
  end
  shuffle(lasts_run)
  for _, t in ipairs(lasts_run) do
    out[#out + 1] = t
  end
  return out
end
if shuffle_seed then
  print("shuffle seed " .. shuffle_seed)
  selected = shuffled(selected, shuffle_seed)
end

-- Only a part whose every test ran is checked: a filter that leaves out
-- the test that puts a setting back must not fail.
local in_part = {}
for _, t in ipairs(tests) do
  if in_pass(t) then in_part[t.part] = (in_part[t.part] or 0) + 1 end
end

-- The options as the run started. The runner gives them back after each
-- test, so a test never sees what an earlier test set: the leak check does
-- not need to look at them.
-- Each window that the screen keeps is drawn too, and a test fails when
-- one drew other cells with the same stamp (paw/ui.tl). It is set
-- before the snapshot of the options, so each test gets it back.
paw.opt.check_stamps = true
local start_options = paw.option.snapshot()
local base = fingerprint()
local leaked = {}
-- The first test of the part that left each kind of kernel state changed,
-- by kind. A test that puts the state back clears its entry.
local left_by = {}
local function note_kernel(t)
  for _, state in ipairs(kernel) do
    if not state.each_part then
      if state.read() == base.kernel[state.kind].label then
        left_by[state.kind] = nil
      elseif not left_by[state.kind] then
        left_by[state.kind] = t.name
      end
    end
  end
end
-- The results ------------------------------------------------------------------
--
-- Each result is a line of the output, which tests/tools/suite.sh reads:
-- "ok", "skip", "FAIL" or "quarantined", then the name of the test, and the
-- error on the lines after it. With PAW_TEST_OUT, it is also a line of TAP in
-- tap.lines, which suite.sh makes into suite.tap for CI: a skip is
-- "# SKIP <reason>", and a quarantined failure is "not ok" with
-- "# TODO quarantined", which TAP does not count as a failure.
local tap = out_dir and io.open(out_dir .. "/tap.lines", "a")

local function report(status, name, detail)
  local indented = detail and ("\n      " .. tostring(detail):gsub("\n", "\n      ")) or ""
  local tap_name = name:gsub("#", "\\#")
  local line
  if status == "ok" then
    print("ok    " .. name .. (detail and (" (" .. detail .. ")") or ""))
    line = "ok - " .. tap_name
  elseif status == "skip" then
    print("skip  " .. name .. " (" .. detail .. ")")
    line = "ok - " .. tap_name .. " # SKIP " .. detail:gsub("#", "\\#")
  elseif status == "quarantined" then
    print("quarantined  " .. name .. " (waits for: " .. quarantined[name] .. ")" .. indented)
    line = "not ok - " .. tap_name .. " # TODO quarantined, waits for: " .. quarantined[name]:gsub("#", "\\#")
  else
    failed = failed + 1
    print("FAIL  " .. name .. indented)
    line = "not ok - " .. tap_name .. (detail and ("\n# " .. tostring(detail):gsub("\n", "\n# ")) or "")
  end
  if tap then
    tap:write(line, "\n")
    tap:flush()
  end
end

local function check(part)
  local now = fingerprint()
  local found = differences(base, now)
  for kind, name in pairs(left_by) do
    if found[kind] then found[kind] = found[kind] .. ' (test "' .. name .. '")' end
  end
  left_by = {}
  reset(base, now)
  -- The runner unloads the extensions that the tests loaded: only one that
  -- it cannot unload, or one that a test unloaded, is a leak.
  found.extensions = differences(base, fingerprint()).extensions
  if whole[part] ~= in_part[part] then return end
  local news = {}
  for _, kind in ipairs(kinds) do
    if found[kind] then
      leaked[part .. " " .. kind] = true
      if not allowed[part .. " " .. kind] then news[#news + 1] = kind .. " " .. found[kind] end
    end
  end
  local name = part .. " leaves no state behind"
  if #news > 0 then
    report("FAIL", name, "changed: " .. table.concat(news, "; "))
  else
    report("ok", name)
  end
end

--- The windows that drew other cells with the same stamp while `fn` ran.
local function stamps_kept(fn)
  local misses = paw.ui.stamp_misses
  for i = #misses, 1, -1 do
    misses[i] = nil
  end
  local skipped = fn()
  if #misses > 0 then error(table.concat(misses, "\n"), 0) end
  return skipped
end

-- Run one test, and report its result.
local function run(t)
  -- An error that came between two tests is of no test.
  reported, expected = {}, {}
  test_began = api.now()
  local ok, err = xpcall(stamps_kept, debug.traceback, t.fn)
  test_began = nil
  for j = #cleanups, 1, -1 do
    pcall(cleanups[j])
    cleanups[j] = nil
  end
  paw.option.restore(start_options)
  note_kernel(t)
  -- A test that skips did not reach what it expects; a test that failed
  -- also names the errors, which can be why.
  local errors = table.concat(unexpected_errors(), "\n")
  if ok and type(err) ~= "string" and errors ~= "" then
    ok, err = false, errors
  elseif not ok and errors ~= "" then
    err = tostring(err) .. "\n" .. errors
  end
  if ok and type(err) == "string" then
    report("skip", t.name, err)
  elseif ok and quarantined[t.name] then
    report("ok", t.name, "quarantined, and it passed: its line can go when the fix is merged")
  elseif ok then
    report("ok", t.name)
  elseif quarantined[t.name] then
    report("quarantined", t.name, err)
  else
    report("FAIL", t.name, err)
  end
end

-- The wall time of each test file, in milliseconds. It is information for
-- a person who looks for a slow file, never a reason to fail.
local spent = {}
for round = 1, rounds do
  local failed_before = failed
  for i, t in ipairs(selected) do
    local started = api.real_ms()
    run(t)
    spent[t.file] = (spent[t.file] or 0) + api.real_ms() - started
    local next_test = selected[i + 1]
    if not next_test or next_test.part ~= t.part then check(t.part) end
  end
  if rounds > 1 and failed > failed_before then
    print(string.format("\nrepeat: run %d of %d failed", round, rounds))
    break
  end
end
if tap then tap:close() end

-- times.txt: one line for each test file, "<ms><tab><file>", the slowest
-- first. The live pass adds its times to those of the pass before it.
if out_dir then
  local path = out_dir .. "/times.txt"
  local file = io.open(path)
  if file then
    for line in file:lines() do
      local ms, name = line:match("^(%d+)\t(.+)$")
      if ms then spent[name] = (spent[name] or 0) + tonumber(ms) end
    end
    file:close()
  end
  local names = {}
  for name in pairs(spent) do
    names[#names + 1] = name
  end
  table.sort(names, function(a, b)
    if spent[a] ~= spent[b] then return spent[a] > spent[b] end
    return a < b
  end)
  file = assert(io.open(path, "w"))
  for _, name in ipairs(names) do
    file:write(string.format("%d\t%s\n", spent[name], name))
  end
  file:close()
end

-- An entry of the allow-list whose part ran whole, its live tests too, and
-- leaked nothing of that kind is out of date: the list only gets shorter.
local has_live = {}
for _, t in ipairs(tests) do
  if t.live then has_live[t.part] = true end
end
local stale = {}
for entry in pairs(allowed) do
  local part = entry:match("^(%S+)")
  if whole[part] and whole[part] == in_part[part] and not has_live[part] and not leaked[entry] then
    stale[#stale + 1] = entry
  end
end
table.sort(stale)
if #stale > 0 then
  report(
    "FAIL",
    "the leak allow-list holds no leak that is gone",
    "remove from " .. allowed_path .. ": " .. table.concat(stale, ", ")
  )
end
failed = failed + golden_unused()
os.execute("rm -rf '" .. scratch .. "'")
local left = {}
for path in pairs(files_before and checkout_files() or {}) do
  -- Code and pages that a person writes while the suite runs, and the golden
  -- screens that PAW_BLESS=1 writes, are not left behind by a test.
  if
    not files_before[path]
    and not path:match("%.rs$")
    and not path:match("%.lua$")
    and not path:match("%.md$")
    and not path:match("/screens/[^/]+/[^/]+%.txt$")
  then
    left[#left + 1] = path
  end
end
table.sort(left)
if #left > 0 then
  report("FAIL", "the tests leave no new files in the checkout", "left: " .. table.concat(left, ", "))
end
print(failed == 0 and "\nall passed" or ("\n" .. failed .. " failed"))
api.quit(failed == 0 and 0 or 1)
