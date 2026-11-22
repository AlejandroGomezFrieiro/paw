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

local tmp = os.getenv("TMPDIR") or "/tmp"
-- The shard's number keeps apart the folders of shards that start at once.
local scratch = tmp
  .. "/paw-test-"
  .. os.time()
  .. "-"
  .. math.floor(api.now() * 1000)
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
-- The part whose tests are being collected (see "Shards" below): each test
-- keeps it, so that the leak check names the part that leaves state behind.
local loading
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn, part = loading } end
-- Tests that run after all the others: those that load every extension.
local lasts = {}
local function last(name, fn) lasts[#lasts + 1] = { name = name, fn = fn, part = loading } end
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
    if api.now() > deadline then error(string.format("waited %d ms in vain for %s", ms, what or "a condition"), 2) end
    paw.wait(5)
  end
end

-- Speed: processor time, and a limit that grows on a loaded machine.
local speed = dofile("tests/tools/speed.lua")
local cpu_ms, quick = speed.cpu_ms, speed.quick

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
      error(
        string.format(
          "the engine ran %d of %d blocks%s in %d ms",
          (api.blocks(device) or 0) - start,
          want - start,
          device and (" of device " .. device) or "",
          ms
        ),
        2
      )
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
  -- Keys half typed, a selection, insert or command line mode, and the
  -- floats an earlier test left open would take this test's first keys.
  local K = paw.keymap
  if K.mode ~= "n" or K.visual or K.pending() ~= "" then K.feed("<Esc><Esc>") end
  while paw.ui.float do
    paw.ui.close()
  end
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
  fresh = fresh,
  start = start,
  screen = screen,
  render = render,
  tone = tone,
  cpu_ms = cpu_ms,
  quick = quick,
  until_ = until_,
  next_block = next_block,
  until_beat = until_beat,
  scratch = scratch,
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
lua_files("tests", "%.lua$")
local extensions = {}
for _, entry in ipairs(api.read_dir("extensions")) do
  if entry.is_dir then extensions[#extensions + 1] = entry.name end
end
table.sort(extensions)
for _, name in ipairs(extensions) do
  lua_files("extensions/" .. name, "^tests[%w_]*%.lua$")
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
    loading = part
    assert(loadfile(path))(T)
  end
end
loading = nil
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

local kinds = { "hooks", "timers", "keys", "extensions", "engine", "midi", "step" }
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

-- State of the kernel that a test can change with the API, outside the
-- registries. `read` gives a label in words, which the check compares, and
-- the value that `put` takes to put it back. `put` runs in the order of the
-- list: an engine restart also empties the MIDI test ports.
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
local selected, whole = {}, {}
for _, t in ipairs(tests) do
  if not only or t.name:find(only, 1, true) then
    selected[#selected + 1] = t
    whole[t.part] = (whole[t.part] or 0) + 1
  end
end
-- Only a part whose every test ran is checked: a filter that leaves out
-- the test that puts a setting back must not fail.
local in_part = {}
for _, t in ipairs(tests) do
  in_part[t.part] = (in_part[t.part] or 0) + 1
end

-- The options as the run started. The runner gives them back after each
-- test, so a test never sees what an earlier test set: the leak check does
-- not need to look at them.
local start_options = paw.option.snapshot()
local base = fingerprint()
local leaked = {}
-- The first test of the part that left each kind of kernel state changed,
-- by kind. A test that puts the state back clears its entry.
local left_by = {}
local function note_kernel(t)
  for _, state in ipairs(kernel) do
    if state.read() == base.kernel[state.kind].label then
      left_by[state.kind] = nil
    elseif not left_by[state.kind] then
      left_by[state.kind] = t.name
    end
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
    failed = failed + 1
    print("FAIL  " .. name .. "\n      changed: " .. table.concat(news, "; "))
  else
    print("ok    " .. name)
  end
end

for i, t in ipairs(selected) do
  local ok, err = xpcall(t.fn, debug.traceback)
  for j = #cleanups, 1, -1 do
    pcall(cleanups[j])
    cleanups[j] = nil
  end
  paw.option.restore(start_options)
  note_kernel(t)
  if ok and type(err) == "string" then
    print("skip  " .. t.name .. " (" .. err .. ")")
  elseif ok then
    print("ok    " .. t.name)
  else
    failed = failed + 1
    print("FAIL  " .. t.name .. "\n      " .. tostring(err):gsub("\n", "\n      "))
  end
  local next_test = selected[i + 1]
  if not next_test or next_test.part ~= t.part then check(t.part) end
end
-- An entry of the allow-list whose part ran whole and leaked nothing of
-- that kind is out of date: the list only gets shorter.
local stale = {}
for entry in pairs(allowed) do
  local part = entry:match("^(%S+)")
  if whole[part] and whole[part] == in_part[part] and not leaked[entry] then stale[#stale + 1] = entry end
end
table.sort(stale)
if #stale > 0 then
  failed = failed + 1
  print(
    "FAIL  the leak allow-list holds no leak that is gone\n      remove from "
      .. allowed_path
      .. ": "
      .. table.concat(stale, ", ")
  )
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
