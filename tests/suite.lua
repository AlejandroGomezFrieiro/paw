-- The runner of the end-to-end tests, and their helpers: `paw --clean -l
-- tests/suite.lua [words]` runs every test (those whose name holds the
-- words). Each test drives the public `paw` module and checks what comes
-- out, including rendered audio.
local paw = require("paw")
local api = paw.api

local tmp = os.getenv("TMPDIR") or "/tmp"
local scratch = tmp .. "/paw-test-" .. os.time() .. "-" .. math.floor(api.now() * 1000)
os.execute("mkdir -p '" .. scratch .. "'")

-- Every file of the checkout outside `target/` and `.git`: at the end,
-- one that is new is a file a test left behind (a clip file named by a
-- clip's id was once written into the current directory).
local function checkout_files()
  -- .claude holds the worktrees of other checkouts, whose own suites write
  -- into them while this one runs.
  local out, pipe = {}, io.popen("find . -path ./target -prune -o -path ./.git -prune -o -path ./.claude -prune -o -type f -print 2>/dev/null")
  if not pipe then return nil end
  for line in pipe:lines() do out[line] = true end
  pipe:close()
  return out
end
local files_before = checkout_files()

local tests, failed = {}, 0
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end
-- Tests that run after all the others: those that load every extension.
local lasts = {}
local function last(name, fn) lasts[#lasts + 1] = { name = name, fn = fn } end
-- What a test asks to have undone when it ends, passed or failed, so that
-- a failure does not leave a setting behind for the tests after it.
local cleanups = {}
local function after(fn) cleanups[#cleanups + 1] = fn end

local function eq(got, want, what)
  if got ~= want then
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

--- Wait until `cond()` gives a value that is not false or nil, and give
--- that value. Timers fire and events come meanwhile, as between key
--- presses (`paw.wait`). Fails with `what` after `ms` milliseconds (30
--- seconds if not given): a loaded machine is slow, not wrong, so give the
--- time that the slowest machine needs, not the time that it usually takes.
local function until_(cond, what, ms)
  ms = ms or 30000
  local deadline = api.now() + ms
  while true do
    local value = cond()
    if value then return value end
    if api.now() > deadline then
      error(string.format("waited %d ms in vain for %s", ms, what or "a condition"), 2)
    end
    paw.wait(5)
  end
end

--- Milliseconds of processor time that this thread has used. A test of
--- speed measures this, not the time on the clock: on a loaded machine the
--- clock runs on while other programs have the processor, and this does
--- not.
local ffi = require("ffi")
pcall(ffi.cdef, "struct paw_timespec { long tv_sec; long tv_nsec; }; int clock_gettime(int, struct paw_timespec *);")
local cpu_now = ffi.new("struct paw_timespec")
local function cpu_ms()
  ffi.C.clock_gettime(3, cpu_now) -- CLOCK_THREAD_CPUTIME_ID
  return tonumber(cpu_now.tv_sec) * 1000 + tonumber(cpu_now.tv_nsec) / 1e6
end

--- How many times more work there is than processors (1 at least): the
--- load average of the last minute over the processors.
local function overload()
  local f = io.open("/proc/loadavg")
  local load = f and tonumber(f:read("*l"):match("^(%S+)")) or 0
  if f then f:close() end
  local p = io.popen("nproc 2>/dev/null")
  local cpus = p and tonumber(p:read("*l") or "") or 1
  if p then p:close() end
  return math.max(1, load / cpus)
end

--- A fixed piece of work with tables, strings and arithmetic, like the
--- work that the speed tests measure.
local function reference_work()
  local t, n = {}, 0
  for i = 1, 20000 do
    t[i] = { i, tostring(i) }
  end
  for i = 1, #t do
    n = n + #t[i][2] + t[i][1] % 7
  end
  table.sort(t, function(x, y) return x[2] < y[2] end)
  return n
end

--- Processor time of `reference_work` on an idle machine, in ms (the
--- smallest of many runs).
local REFERENCE_IDLE_MS = 8.0

--- How many times slower this thread runs now than on an idle machine
--- (1 at least, 8 at most): the best of three runs of `reference_work`
--- against its time on an idle machine. Contention for the caches and the
--- memory inflates processor time, and the load average does not show it.
local function slowdown()
  local best = math.huge
  for _ = 1, 3 do
    local t0 = cpu_ms()
    reference_work()
    best = math.min(best, cpu_ms() - t0)
  end
  return math.min(8, math.max(1, best / REFERENCE_IDLE_MS))
end

--- Check that `ms` of processor time (`cpu_ms`) is under `limit`. Programs
--- that share the processor's caches and memory make the same work take
--- more processor time: the limit grows with the overload of the machine
--- and with the slowdown of a fixed piece of work (at most 8 times).
local function quick(ms, limit, what)
  local over = overload()
  local slow = slowdown()
  local allowed = limit * math.max(over, slow)
  if ms >= allowed then
    error(string.format("%s: %.0f ms of processor time, the limit %.0f ms (%d ms times %.1f: overload %.1f, slowdown %.1f)",
      what, ms, allowed, limit, math.max(over, slow), over, slow), 2)
  end
end

--- Wait until the engine has run `n` (1 if not given) whole audio blocks
--- after this call, so that what was sent to it before is in effect: a
--- parameter, a note, a change to a track. Changes not yet sent are sent
--- first. With `device`, count the blocks that this device ran: a device
--- that sleeps through silence does not count them. Fails after `ms`
--- milliseconds (10 seconds if not given).
local function next_block(n, device, ms)
  paw.flush()
  ms = ms or 10000
  -- The block under way may have started before the change came: the
  -- next one to finish does not count.
  local start = api.blocks(device)
  if start == nil then error("the engine has no device " .. tostring(device), 2) end
  local want = start + (n or 1) + 1
  local deadline = api.now() + ms
  while (api.blocks(device) or 0) < want do
    if api.now() > deadline then
      error(string.format("the engine ran %d of %d blocks%s in %d ms", (api.blocks(device) or 0) - start,
        want - start, device and (" of device " .. device) or "", ms), 2)
    end
    api.sleep(1)
  end
end

--- Wait until the playhead, after it went round the loop `rounds` times (0
--- if not given), is at `beat` or past it. A test that plays or records
--- waits for the playhead, not for a time: on a loaded machine a time
--- slept is longer than the time asked for.
local function until_beat(beat, rounds, ms)
  local before, wraps = paw.transport.position, 0
  until_(function()
    local now = paw.transport.position
    if now < before then wraps = wraps + 1 end
    before = now
    return wraps >= (rounds or 0) and now >= beat
  end, string.format("the playhead at beat %g after %d times round the loop", beat, rounds or 0), ms or 30000)
end

local function fresh()
  paw.project.new()
  paw.transport.loop_enabled = false
  -- The windows and tabs an earlier test opened would share the screen
  -- with this one's: each test starts from the default start layout.
  local L = require("paw.layout")
  if #paw.ui.tabs > 1 or #L.windows(paw.ui.layout) ~= 1 or L.windows(paw.ui.layout)[1].view ~= "arrange" then
    L.restore({ { layout = L.default_tree() } })
  end
  paw.ui.close()
  paw.ui.focus("arrange")
  paw.flush()
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

local fixtures = "tests/fixtures/"

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
    for beat = 0, 3 do notes[#notes + 1] = { pitch = 60 + beat, start = beat, length = 1 } end
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
  for i, n in ipairs(notes) do notes[i] = string.format("%d@%g+%g", n.pitch, n.start, n.length) end
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

local T = {
  test = test, last = last, after = after, eq = eq, near = near, fails = fails, fresh = fresh, render = render, tone = tone, cpu_ms = cpu_ms, quick = quick,
  until_ = until_, next_block = next_block, until_beat = until_beat,
  scratch = scratch, read_file = read_file, write_file = write_file, frequency = frequency,
  channel_peaks = channel_peaks, three_clips = three_clips, layout = layout, melody = melody, keys = keys,
  roll_notes = roll_notes,
}
local files = {}
local function lua_files(dir, pattern)
  local found = {}
  for _, entry in ipairs(api.read_dir(dir)) do
    if not entry.is_dir and entry.name:match(pattern) and entry.name ~= "suite.lua" then
      found[#found + 1] = dir .. "/" .. entry.name
    end
  end
  table.sort(found)
  for _, path in ipairs(found) do files[#files + 1] = path end
end
lua_files("tests", "%.lua$")
local extensions = {}
for _, entry in ipairs(api.read_dir("extensions")) do
  if entry.is_dir then extensions[#extensions + 1] = entry.name end
end
table.sort(extensions)
for _, name in ipairs(extensions) do lua_files("extensions/" .. name, "^tests[%w_]*%.lua$") end
for _, path in ipairs(files) do assert(loadfile(path))(T) end
for _, t in ipairs(lasts) do tests[#tests + 1] = t end

-- Run ------------------------------------------------------------------------

local only = ...
for _, t in ipairs(tests) do
  if not only or t.name:find(only, 1, true) then
    local ok, err = xpcall(t.fn, debug.traceback)
    for i = #cleanups, 1, -1 do pcall(cleanups[i]) cleanups[i] = nil end
    if ok and type(err) == "string" then
      print("skip  " .. t.name .. " (" .. err .. ")")
    elseif ok then
      print("ok    " .. t.name)
    else
      failed = failed + 1
      print("FAIL  " .. t.name .. "\n      " .. tostring(err):gsub("\n", "\n      "))
    end
  end
end
os.execute("rm -rf '" .. scratch .. "'")
local left = {}
for path in pairs(files_before and checkout_files() or {}) do
  -- Code and pages that a person writes while the suite runs are not left
  -- behind by a test.
  if not files_before[path] and not path:match("%.rs$") and not path:match("%.lua$") and not path:match("%.md$") then
    left[#left + 1] = path
  end
end
table.sort(left)
if #left > 0 then
  failed = failed + 1
  print("FAIL  the tests leave no new files in the checkout\n      left: " .. table.concat(left, ", "))
end
print(failed == 0 and "\nall passed" or ("\n" .. failed .. " failed"))
api.quit(failed == 0 and 0 or 1)
