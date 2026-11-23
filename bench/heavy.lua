-- Large inputs: the processor time of the kernel's own work on them.
--   paw --clean --no-plugins -l bench/heavy.lua [case ...] [reps=N]
-- The suite measured these as pass/fail tests until the test lint. A test now
-- checks the behavior, and this script measures the time. Each case runs
-- `reps` times (default 5) on a new project and prints one JSON line:
-- `cpu_ms_median`, `cpu_ms_min` and `cpu_ms_max` (the processor time of
-- the kernel's thread), and the load average. With no case, all run.
--
-- Cases:
--   notation_open   a clip of more than 10 000 notes opened as notation and drawn at 150x45
--   notation_moves  in that view, twenty cursor moves and a draw
--   picker          a picker of 6 000 items, eight keys, each with a draw at 120x40
--   search          100 parts of 100 notes: a query, a grep of lyrics, the notes picker
--   legato          musicops' legato on 10 000 notes
--   pattern_errors  the pattern text that asks for too many notes, refused
--   help            the help index made at idle: the longest slice, then the first :help
--   utau_block      400 blocks of 512 frames of the vocal device where four phrases sound
--   grid_moves      500 bars with 50 meter changes on a 1/16 grid with swing: 20 `l`, `999l` and `999h`, each drawn at 150x45
--
-- The paint of the notation view is in extensions/notation/tools/paintbench.lua.
local paw = require("paw")
local api = paw.api
local B = dofile(debug.getinfo(1, "S").source:sub(2):match("(.*)/") .. "/lib.lua")

local wanted, reps = {}, 5
for _, arg in ipairs({ ... }) do
  local n = arg:match("^reps=(%d+)$")
  if n then
    reps = tonumber(n)
  else
    wanted[arg] = true
  end
end

local function extension(name)
  if not (paw.ext.loaded[name] and paw.ext.loaded[name].ok) then paw.ext.load("extensions/" .. name) end
  return require(name)
end

--- A new project in the start layout, as the suite's `T.fresh` makes.
local function new_project()
  paw.keymap.feed("<Esc><Esc>")
  paw.project.new()
  local L = require("paw.layout")
  L.restore({ { layout = L.default_tree() } })
  paw.ui.close()
  paw.ui.focus("arrange")
  paw.flush()
end

--- The processor time of `measure(state)` in ms, after `setup()` made the
--- state on a new project. `setup` is not measured.
local function timed(setup, measure)
  new_project()
  local state = setup and setup() or nil
  collectgarbage()
  local t0 = B.cpu_ms()
  measure(state)
  return B.cpu_ms() - t0
end

local cases = {}
local order = {}
local function case(name, setup, measure)
  cases[name] = { setup = setup, measure = measure }
  order[#order + 1] = name
end

-- Notation on a big clip ------------------------------------------------------------

local function big_notation_clip()
  extension("notation")
  local notes = require("notation.bench").notes(690)
  local part = paw.add_part({ name = "Big" })
  part:add_clip({ start = 0, length = 690 * 4, name = "big", notes = notes })
  paw.flush()
  api.undo_checkpoint()
  paw.cursor.set_part(part)
  paw.cursor.beat = 0
  api.ui_snapshot(150, 45)
end

case("notation_open", big_notation_clip, function()
  paw.keymap.feed(":notation<CR>")
  api.ui_snapshot(150, 45)
end)

case("notation_moves", function()
  big_notation_clip()
  paw.keymap.feed(":notation<CR>")
  api.ui_snapshot(150, 45)
end, function()
  for _ = 1, 20 do
    paw.keymap.feed("l")
  end
  api.ui_snapshot(150, 45)
end)

-- Moves on the grid of time ---------------------------------------------------------

-- 500 bars with 50 meter changes, a 1/16 grid with swing, and the cursor
-- in the middle: the lines of the grid follow each change.
case("grid_moves", function()
  local meters = { { 7, 8 }, { 5, 4 }, { 3, 4 }, { 6, 8 }, { 4, 4 } }
  for i = 1, 50 do
    local m = meters[(i - 1) % #meters + 1]
    paw.tempo.set_signature(i * 10, m[1], m[2])
  end
  local part = paw.add_part({ name = "Long" })
  part:add_clip({ start = 0, length = paw.time.bar_start(501), name = "long" })
  paw.flush()
  api.undo_checkpoint()
  paw.cursor.set_part(part)
  paw.cursor.set_beat(paw.time.bar_start(250))
  paw.opt.grid, paw.opt.swing = "1/16", 60
  api.ui_snapshot(150, 45)
end, function()
  for _ = 1, 20 do
    paw.keymap.feed("l")
    api.ui_snapshot(150, 45)
  end
  paw.keymap.feed("999l")
  api.ui_snapshot(150, 45)
  paw.keymap.feed("999h")
  api.ui_snapshot(150, 45)
end)

-- The picker and search --------------------------------------------------------------

case("picker", function()
  local words = { "Dragonfly", "Hall", "Plate", "Room", "Delay", "Chorus", "EQ", "Gate", "Tape", "Synth" }
  local items = {}
  for i = 1, 6000 do
    items[i] = "clap:vendor." .. words[i % #words + 1] .. " " .. words[(i * 7) % #words + 1] .. " " .. i
  end
  return items
end, function(items)
  paw.pick({ items = items, on_choose = function() end })
  for _, key in ipairs({ "d", "r", "a", "<Space>", "h", "<BS>", "<BS>", "g" }) do
    paw.keymap.feed(key)
    api.ui_snapshot(120, 40)
  end
  paw.keymap.feed("<Esc>")
end)

case("search", function()
  for i = 1, 100 do
    local notes = {}
    for k = 1, 100 do
      notes[k] = { 48 + (k % 24), (k - 1) * 0.25, 0.25, 90, meta = k % 10 == 0 and { lyric = "la" .. k } or nil }
    end
    paw.add_part({ name = "Part " .. i }):add_clip({ name = "clip " .. i, start = 0, length = 32, notes = notes })
  end
  paw.flush()
end, function()
  paw.query("part[name$=7] > clip > note[pitch>=C4][vel>80]")
  paw.grep.search("la1", { mode = "exact" })
  paw.pick("notes")
  paw.keymap.feed("C5 la")
  paw.keymap.feed("<Esc>")
end)

-- Extensions -------------------------------------------------------------------------

case("legato", function()
  extension("musicops")
  local notes = {}
  for i = 1, 10000 do
    notes[i] = { pitch = 60 + i % 12, start = (i - 1) * 0.25 + (i % 3) * 0.01, length = 0.1, velocity = 100 }
  end
  return notes
end, function(notes) require("musicops").legato(notes) end)

case("pattern_errors", function() return extension("pattern") end, function(pattern)
  assert(not pcall(pattern.notes, "bd*100000", 1), "a repeat past 256 is refused")
  assert(not pcall(pattern.notes, "[bd*256]*256", 4), "too many notes are refused")
end)

local UTAU_BLOCKS = 400
case("utau_block", function()
  local utau = extension("utau")
  local ffi = require("ffi")
  local dev = assert(loadfile("extensions/utau/devices/utau.lua"))()
  local rate, frames = 48000, 512
  dev.init(rate)
  local lines = {}
  for k = 0, 7 do
    local path = utau.voices.dir() .. "/bench-" .. k .. ".f32"
    local n = 2 * 44100
    local buf = ffi.new("float[?]", n)
    for i = 0, n - 1 do
      buf[i] = 0.5 * math.sin(2 * math.pi * (220 + k * 30) * i / 44100)
    end
    local f = assert(io.open(path, "wb"))
    f:write(ffi.string(buf, n * 4))
    f:close()
    lines[#lines + 1] = string.format("b%d %g 44100 1 1 %s", k, k * 0.25, path)
  end
  dev.call("voice.1", table.concat(lines, "\n"))
  local b = {
    left = ffi.new("float[?]", frames),
    right = ffi.new("float[?]", frames),
    frames = frames,
    params = { voice = 1 },
    sample_rate = rate,
    playing = true,
    tempo = 120,
    seconds = 1.0,
  }
  for _ = 1, 50 do
    dev.process(b)
  end
  return { dev = dev, b = b }
end, function(s)
  for i = 1, UTAU_BLOCKS do
    -- Where four phrases overlap at once.
    s.b.seconds = 1.0 + (i % 40) * 512 / 48000
    s.dev.process(s.b)
  end
end)

-- Help -------------------------------------------------------------------------------

--- The help index made at idle in slices: the longest slice, which a key
--- waits for. Reported apart from the measure of the case.
local help_slice = {}
case("help", function()
  local H = paw.help
  H.dirty = true
  H.prepare()
  local longest = 0
  while H.preparing() do
    local t0 = B.cpu_ms()
    paw.wait(1)
    longest = math.max(longest, B.cpu_ms() - t0)
  end
  help_slice[#help_slice + 1] = longest
end, function()
  paw.keymap.feed(":help gU<CR>")
  paw.keymap.feed(":q<CR>")
end)

-- The run ------------------------------------------------------------------------------

local function emit(name, times, extra)
  local s = B.stats(times)
  local record = {
    bench = "heavy",
    case = name,
    reps = #times,
    cpu_ms_median = s.p50,
    cpu_ms_min = math.min(unpack(times)),
    cpu_ms_max = s.max,
    load = B.load(),
  }
  for k, v in pairs(extra or {}) do
    record[k] = v
  end
  B.emit(record)
end

for _, name in ipairs(order) do
  if next(wanted) == nil or wanted[name] then
    local c = cases[name]
    local times = {}
    for i = 1, reps do
      times[i] = timed(c.setup, c.measure)
    end
    if name == "help" then
      local s = B.stats(help_slice)
      emit(name, times, { longest_slice_ms_median = s.p50, longest_slice_ms_max = s.max })
    elseif name == "utau_block" then
      local each = B.stats(times).p50 / UTAU_BLOCKS * 1000
      emit(name, times, { us_per_block_median = each, block_lasts_us = 512 / 48000 * 1e6 })
    else
      emit(name, times)
    end
  end
end
