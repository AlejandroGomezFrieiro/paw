-- The grid of time (paw/timegrid.tl): positions are whole ticks, and the
-- lines of each kind of grid, over meter and tempo changes, folds and a
-- scope, hold the rules that the motions rely on. The positions come from
-- fixed seeds: the same run each time. Loaded by tests/suite.lua with its
-- helpers.
local T = ...
local test, eq = T.test, T.eq
local timegrid = paw.timegrid
local TPQ = timegrid.TPQ

--- A list of numbers from a fixed seed (a linear congruential generator):
--- `next_int(n)` gives 0 to n - 1.
local function generator(seed)
  local state = seed
  return function(n)
    state = (state * 1103515245 + 12345) % 2147483648
    return state % n
  end
end

-- A tempo map of constant parts, `{ tick, bpm }` from tick 0: seconds at a
-- tick, and the tick at a time.
local function tempo_map(points)
  local starts = { 0 }
  for i = 2, #points do
    local a, b = points[i - 1], points[i]
    starts[i] = starts[i - 1] + (b[1] - a[1]) / TPQ * 60 / a[2]
  end
  local function seconds(t)
    local i = #points
    while points[i][1] > t do
      i = i - 1
    end
    return starts[i] + (t - points[i][1]) / TPQ * 60 / points[i][2]
  end
  local function tick_at(s)
    local i = #points
    while starts[i] > s do
      i = i - 1
    end
    return points[i][1] + (s - starts[i]) * points[i][2] / 60 * TPQ
  end
  return seconds, tick_at
end

local BAR = 4 * TPQ
-- 4/4, then 7/8 from bar 3, then 5/4 from the bar after two of 7/8.
local CHANGES = {
  { tick = 0, num = 4, den = 4 },
  { tick = 2 * BAR, num = 7, den = 8 },
  { tick = 2 * BAR + 7 * TPQ, num = 5, den = 4 },
}
local seconds, tick_at = tempo_map({ { 0, 120 }, { 16 * TPQ, 90 }, { 41 * TPQ + 77, 140 } })

-- The grids of the property test: each kind of setting, with what moves
-- its lines.
local GRIDS = {
  { setting = "1/4" },
  { setting = "1/8t", meter = CHANGES },
  { setting = "1/16", swing = 60, meter = CHANGES },
  { setting = "1/7", meter = CHANGES },
  { setting = "bar", meter = CHANGES },
  { setting = "frame", frame_rate = 30000 / 1001, seconds = seconds, tick_at = tick_at },
  { setting = "1s", seconds = seconds, tick_at = tick_at },
  { setting = 0.75, meter = CHANGES },
  -- A closed fold that starts and ends off the grid, and a scope.
  {
    setting = "1/8",
    meter = CHANGES,
    folds = { { from = 5 * TPQ + 1000, to = 9 * TPQ + 7 } },
    scope = { from = TPQ + 300, to = 40 * TPQ },
  },
}

local function name_of(spec)
  local parts = { tostring(spec.setting) }
  if spec.swing then parts[#parts + 1] = "swing " .. spec.swing end
  if spec.meter then parts[#parts + 1] = "meter changes" end
  if spec.folds then parts[#parts + 1] = "a fold and a scope" end
  return table.concat(parts, ", ")
end

local SPAN = 48 * TPQ

test("timegrid: lines are whole ticks, sorted and unique, and next and prev go to lines", function()
  for _, spec in ipairs(GRIDS) do
    local g = timegrid.new(spec)
    local what = name_of(spec)
    -- The lines past the span too: next(t) of a t near its end.
    local lines = g:lines(0, SPAN + 2 * BAR)
    local is_line = {}
    for i, line in ipairs(lines) do
      eq(timegrid.is_tick(line), true, what .. ": line " .. i .. " is a whole tick")
      if i > 1 then eq(line > lines[i - 1], true, what .. ": line " .. i .. " is after the one before") end
      is_line[line] = true
    end
    eq(#lines > 8, true, what .. ": lines in " .. SPAN / TPQ .. " beats")
    local random = generator(7)
    for _ = 1, 300 do
      -- A position in the scope: outside it, the cursor never is.
      local t = g.lo + random(math.min(g.hi, SPAN) - g.lo)
      local after, before = g:next(t), g:prev(t)
      eq(is_line[after] or after == g.hi, true, what .. ": next(" .. t .. ") is a line")
      eq(is_line[before] or before == g.lo, true, what .. ": prev(" .. t .. ") is a line")
      eq(after > t or t >= g.hi, true, what .. ": next(" .. t .. ") is later")
      eq(before < t or t <= g.lo, true, what .. ": prev(" .. t .. ") is earlier")
      eq(g:next(before) >= t, true, what .. ": next(prev(" .. t .. "))")
      eq(g:prev(after) <= t, true, what .. ": prev(next(" .. t .. "))")
      local line = g:floor(t)
      eq(is_line[line] and line <= t, true, what .. ": floor(" .. t .. ") is the line before or at it")
      eq(g:off(t), t - line, what .. ": off(" .. t .. ")")
      if t > g.lo and t < g.hi and line == t then
        eq(g:prev(g:next(t)), t, what .. ": prev(next(" .. t .. ")) on the grid")
      end
      local near, from, to = g:nearest(t), g:cell(t)
      eq(from <= t and (t < to or t >= g.hi), true, what .. ": the cell of " .. t .. " holds it")
      eq(near == from or near == to, true, what .. ": nearest(" .. t .. ") is an edge of its cell")
    end
  end
end)

test("timegrid: n lines forward and n back give the same tick, and a whole move keeps its offset", function()
  for _, spec in ipairs(GRIDS) do
    local g = timegrid.new(spec)
    local what = name_of(spec)
    local random = generator(11)
    for _ = 1, 100 do
      local n = 1 + random(60)
      local start = g:floor(random(SPAN))
      local t = start
      for _ = 1, n do
        t = g:next(t)
      end
      if t < g.hi then
        for _ = 1, n do
          t = g:prev(t)
        end
        eq(t, start, what .. ": " .. n .. " lines forward and back from " .. start)
      end
      -- A thing off the grid keeps its offset, and comes back, when the
      -- cell it lands in is long enough for the offset.
      local a = start + random(g:width(start))
      local moved = g:steps(a, n)
      if moved < g.hi and g:off(moved) == g:off(a) then
        eq(g:steps(moved, -n), a, what .. ": steps(steps(" .. a .. ", " .. n .. "), -" .. n .. ")")
      end
    end
  end
  -- On a grid whose cells are all one length, every offset fits.
  local g = timegrid.new({ setting = "1/16" })
  local random = generator(3)
  for _ = 1, 200 do
    local a, n = random(SPAN), random(100) - 50
    eq(g:steps(g:steps(a + 100 * TPQ, n), -n), a + 100 * TPQ, "1/16: a move by " .. n .. " and back")
  end
end)

test("timegrid: lines start again at each bar, and a long run of steps does not drift", function()
  local g = timegrid.new({ setting = "1/4", meter = CHANGES })
  -- The 7/8 bars have a short last cell; each bar line is a line.
  eq(g:lines(2 * BAR, 2 * BAR + 7 * TPQ + 1), {
    2 * BAR,
    2 * BAR + TPQ,
    2 * BAR + 2 * TPQ,
    2 * BAR + 3 * TPQ,
    2 * BAR + 3.5 * TPQ,
    2 * BAR + 4.5 * TPQ,
    2 * BAR + 5.5 * TPQ,
    2 * BAR + 6.5 * TPQ,
    2 * BAR + 7 * TPQ,
  }, "1/4 over two bars of 7/8")
  -- 1/8t in 4/4: twelve lines a bar, so line 12 000 is bar 1000.
  local triplets = timegrid.new({ setting = "1/8t" })
  local t = 0
  for _ = 1, 12000 do
    t = triplets:next(t)
  end
  eq(t, 1000 * BAR, "12000 triplets from 0")
  -- 1/7 is no whole number of ticks: each line is the nearest tick to its
  -- place in the bar, and the seventh is the bar line.
  local sevenths = timegrid.new({ setting = "1/7" })
  eq(sevenths:lines(500 * BAR, 501 * BAR + 1)[8], 501 * BAR, "seven lines of 1/7 to the next bar")
  eq(sevenths:lines(500 * BAR, 501 * BAR)[2], 500 * BAR + 35109, "4/7 of a beat, to the nearest tick")
  -- Swing: each second line later, by (60 - 50) % x 2 of a step.
  local swung = timegrid.new({ setting = "1/8", swing = 60 })
  eq(swung:lines(0, TPQ * 2), { 0, TPQ / 2 + TPQ / 10, TPQ, TPQ * 3 / 2 + TPQ / 10 }, "1/8 at 60 % swing")
end)

test("timegrid: the settings, and an option that is not one", function()
  for _, case in ipairs({
    { "1/4", TPQ },
    { "1/8t", TPQ / 3 },
    { "1/16", TPQ / 4 },
    { 0.5, TPQ / 2 },
  }) do
    local s = timegrid.parse(case[1])
    eq(s.num / s.den, case[2], "the step of " .. tostring(case[1]))
  end
  eq(timegrid.parse("bar").kind, "bar", "bar")
  eq(timegrid.parse("500ms").period, 0.5, "500ms")
  eq(timegrid.parse("frame").kind, "frame", "frame")
  eq(timegrid.parse("1/8x"), nil, "1/8x is no setting")
  eq(timegrid.new({ setting = "auto", zoom = 2 }):width(0), TPQ, "auto at 2 columns a beat: a beat")
  eq(timegrid.new({ setting = "auto", zoom = 16 }):width(0), TPQ / 8, "auto at 16: 1/32")
  T.fails(
    function() paw.opt.grid = "1/8x" end,
    "grid takes a number of beats, a note value",
    "an option that is not one"
  )
end)

test("timegrid: a tick with a fraction is refused in the tests, a beat becomes the nearest tick", function()
  T.fresh()
  T.fails(function() paw.cursor.set_tick(TPQ / 7) end, "not a whole number of ticks", "set_tick(1/7 of a beat)")
  paw.cursor.set_beat(1 / 3)
  eq(paw.cursor.tick, TPQ / 3, "a third of a beat")
  paw.cursor.set_beat(4 / 7)
  eq(paw.cursor.tick, 35109, "4/7 of a beat, to the nearest tick")
  eq(paw.cursor.beat, 35109 / TPQ, "the beat is the tick's")
end)

test("timegrid: the window's grid follows the meter, and zoom and scroll change no line", function()
  T.fresh()
  paw.tempo.set_signature(3, 7, 8)
  paw.opt.grid = "1/4"
  local g = timegrid.window()
  eq(g:lines(2 * BAR, 2 * BAR + 4 * TPQ), {
    2 * BAR,
    2 * BAR + TPQ,
    2 * BAR + 2 * TPQ,
    2 * BAR + 3 * TPQ,
    2 * BAR + 3.5 * TPQ,
  }, "the lines over the 7/8 bar")
  local before = g:lines(0, SPAN)
  paw.cursor.set_beat(5)
  paw.opt.zoom = 7
  T.keys("<Esc>zozizi")
  eq(timegrid.window():lines(0, SPAN), before, "the lines after zoom and scroll")
  eq(paw.cursor.tick, 5 * TPQ, "the cursor after zoom and scroll")
end)

test("timegrid: :grid 1/8t and swing 60, 999l then 999h, gives back the same whole tick", function()
  T.start()
  T.keys(":grid 1/8t<CR>")
  T.keys(":set swing=60<CR>")
  eq(paw.opt.grid, "1/8t", "the grid")
  T.keys("]g")
  eq(paw.opt.grid, "1/4t", "]g: a coarser triplet")
  T.keys("[g")
  eq(paw.opt.grid, "1/8t", "[g: back")
  local t = 0
  for _ = 1, 30 do
    T.keys("l")
    eq(timegrid.is_tick(paw.cursor.tick), true, "a whole tick after l")
    eq(paw.cursor.tick > t, true, "l moves on")
    t = paw.cursor.tick
  end
  eq(t, 10 * TPQ, "30 triplets of eighths are 10 beats")
  T.keys("999l")
  local far = paw.cursor.tick
  -- Line 1029 is the tenth of its bar: the second of a pair, so it swings
  -- by a fifth of a step.
  eq(far, 343 * TPQ + TPQ / 15, "999 triplets of eighths more are 333 beats, and a swing")
  T.keys("999h")
  eq(paw.cursor.tick, 10 * TPQ, "999h comes back")
end)
