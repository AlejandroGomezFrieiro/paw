-- Tests of the waveform an audio clip shows in cells: one column of peaks
-- from lowest to highest sample, around the middle, in eighth blocks, and
-- in the error colour where the wave reaches full scale. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

--- A mono 16-bit file of one second at 48 kHz that is silent but for one
--- burst of `level`, alternating in sign, from 0.25 s to 0.28125 s: inside a single column of a
--- clip drawn 16 columns wide, and well apart from the clip's start.
local function burst_file(name, level)
  local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
  local function u32(v) return u16(v % 65536) .. u16(math.floor(v / 65536)) end
  local samples = {}
  for i = 1, 48000 do
    local v = (i > 12000 and i <= 13500) and (i % 2 == 0 and level or -level) or 0
    local q = math.floor(v * 32767 + 0.5)
    samples[i] = u16(q < 0 and q + 65536 or q)
  end
  local data = table.concat(samples)
  local path = T.scratch .. "/" .. name .. ".wav"
  T.write_file(
    path,
    "RIFF"
      .. u32(36 + #data)
      .. "WAVEfmt "
      .. u32(16)
      .. u16(1)
      .. u16(1)
      .. u32(48000)
      .. u32(96000)
      .. u16(2)
      .. u16(16)
      .. "data"
      .. u32(#data)
      .. data
  )
  return path
end

--- The characters of a line, one for each cell.
local function chars(line)
  local out = {}
  for c in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    out[#out + 1] = c
  end
  return out
end

--- The columns (from 0) where the rows have anything in them.
local function lit_columns(rows)
  local lit = {}
  for _, row in ipairs(rows) do
    for i, c in ipairs(chars(row)) do
      if c ~= " " then lit[i - 1] = true end
    end
  end
  return lit
end

local function clip_with(level, gain)
  fresh()
  local t = paw.add_part({ name = "hits" })
  local clip = t:add_clip({ start = 0, file = burst_file("burst" .. level, level), gain = gain })
  paw.cursor.set_part(t)
  return t, clip
end

test("a hit shows in its own column of the waveform, as a thin line when quiet and a tall one when loud", function()
  local _, clip = clip_with(0.8)
  local rows = paw.draw.waveform(clip:peaks(16), 4)
  local lit = lit_columns(rows)
  eq(lit[4], true, "the hit is in the column where it sounds")
  local count = 0
  for _ in pairs(lit) do
    count = count + 1
  end
  eq(count, 1, "and nowhere else")
  -- 0.8 of the way up and down: all four rows are drawn there.
  for row = 1, 4 do
    eq(chars(rows[row])[5] ~= " ", true, "row " .. row .. " has the hit")
  end
  eq(chars(rows[1])[5], "▅", "the top row is filled from its bottom up to the 0.8 mark, five eighths of it")
  eq(chars(rows[4])[5], "▃", "and the bottom one from its top down, three eighths, drawn in reverse")

  local _, quiet = clip_with(0.1)
  rows = paw.draw.waveform(quiet:peaks(16), 4)
  eq(chars(rows[1])[5], " ", "a quiet hit does not reach the top row")
  eq(chars(rows[2])[5] ~= " " and chars(rows[3])[5] ~= " ", true, "it is drawn on both sides of the middle")
end)

test("columns that reach full scale, after the clip's gain, are drawn in the error colour", function()
  local function marks(level, gain)
    local _, clip = clip_with(level, gain)
    local _, runs = paw.draw.waveform(clip:peaks(16), 3)
    local out = {}
    for row = 1, 3 do
      for _, run in ipairs(runs[row]) do
        if run.mark and run.mark:find("clip") then out[#out + 1] = run.column .. ":" .. #chars(run.text) end
      end
    end
    return out
  end
  eq(table.concat(marks(1.0), ","), "4:1,4:1,4:1", "a column at full scale, in every row it is drawn in")
  eq(#marks(0.5), 0, "half scale is not clipping")
  eq(#marks(0.6, 6.0206), 3, "but it is when the clip's gain brings it to full scale")
  eq(#marks(1.0, -6.0206), 0, "and it is not when the gain takes it below")

  -- On the screen the column is red whichever way up its cells are drawn.
  local _ = clip_with(1.0)
  paw.opt.zoom, paw.opt.part_height = 8, 4
  local red = require("paw.theme").palette.red
  local found = 0
  for _, row in ipairs(api.ui_view_snapshot("arrange", 100, 30).rows) do
    for _, run in ipairs(row) do
      if run.fg == red or run.bg == red then found = found + 1 end
    end
  end
  paw.opt.zoom, paw.opt.part_height = 2, "auto"
  eq(found >= 3, true, "the clipping cells are red on the screen: " .. found)
end)

test("zooming draws the waveform again from the peaks, and the hit stays at its time", function()
  clip_with(0.8)
  paw.opt.part_height = 4
  local function column_of_hit(zoom)
    paw.opt.zoom = zoom
    local lines = api.ui_snapshot(100, 30)
    local hw = paw.ui.views:get("arrange").geometry.hw
    for y, line in ipairs(lines) do
      if line:find("burst", 1, true) or (line:find("hits", 1, true) and line:find("▏", 1, true)) then
        local rows = { lines[y + 1], lines[y + 2], lines[y + 3] }
        local lit = lit_columns(rows)
        for x = hw + 1, 99 do
          if lit[x] then return x - hw end
        end
      end
    end
  end
  eq(column_of_hit(4), 2, "a quarter of a second is half a beat: two columns at 4 to a beat")
  eq(column_of_hit(8), 4, "and four columns at 8")
  paw.opt.zoom, paw.opt.part_height = 2, "auto"
end)

test("the waveform is the same in cells with graphics on and off, and in ASCII it is still a shape", function()
  local _, clip = clip_with(1.0)
  paw.opt.zoom, paw.opt.part_height = 8, 4
  paw.opt.graphics = true
  local on = table.concat(api.ui_snapshot(100, 30), "\n")
  paw.opt.graphics = false
  local off = table.concat(api.ui_snapshot(100, 30), "\n")
  paw.opt.graphics = true
  eq(on, off, "pure cells either way")
  paw.opt.ascii = true
  local rows = paw.draw.waveform(clip:peaks(16), 3)
  paw.opt.ascii = false
  local lit = lit_columns(rows)
  eq(lit[4], true, "ASCII draws the hit too")
  for _, row in ipairs(rows) do
    eq(row:find("[\128-\255]") == nil, true, "with nothing outside ASCII: " .. row)
  end
  paw.opt.zoom, paw.opt.part_height = 2, "auto"
end)

test("a decibel scale makes quiet sound reach further than the linear one does", function()
  local _, clip = clip_with(0.05)
  local linear = paw.draw.waveform(clip:peaks(16), 3)
  paw.opt.wave_scale = "db"
  local db = paw.draw.waveform(clip:peaks(16), 3)
  paw.opt.wave_scale = "linear"
  eq(chars(linear[1])[5], " ", "linear: -26 dB is too small to leave the middle row")
  eq(chars(db[1])[5] ~= " ", true, "decibels: it reaches the top row")
end)
