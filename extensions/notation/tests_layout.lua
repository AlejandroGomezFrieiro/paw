-- Tests of the engraved page's layout: skylines and what is placed against
-- them, balanced system breaks and the breaks a score keeps, slurs, the
-- page view and its export. Loaded by tests/suite.lua.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local paw = require("paw")
local api = paw.api

local function load()
  if not package.loaded["notation.keys"] then paw.ext.load("extensions/notation") end
  return require("notation")
end

local function N(pitch, start, length) return { pitch = pitch, start = start, length = length, velocity = 80 } end

local keys = T.keys

local W, H = 1053, 900
local function paint(view)
  paw.canvas.paint("notation", W, H, { cell = { w = 7.8, h = 17 } })
  return view.gui.engraved
end

--- A score clip open as notation, from notes.
local function score(notes, length)
  fresh()
  local view = load()
  view.page, view.galley, view.space = false, false, nil
  local part = paw.add_part({ name = "Piano" })
  local clip = part:add_clip({ start = 0, length = length, name = "tune", notes = notes })
  paw.flush()
  paw.keymap.set_mode("n")
  view:edit(clip)
  paw.ui.focus("notation")
  api.undo_checkpoint()
  return view, clip
end

--- A grand staff of 16 dense bars: ledger lines both ways, runs, triplets,
--- chords, dynamics and hairpins (over barlines and systems), slurs over
--- high notes, text and lyrics.
local function dense()
  local notes, seed = {}, 11
  local function rnd(n)
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed % n
  end
  local high = { 72, 74, 76, 79, 81, 84, 86, 88, 91, 93 }
  for bar = 0, 15 do
    local t = 0
    while t < 4 - 1e-9 do
      if bar % 4 == 1 and t == 0 then
        for k = 0, 2 do
          notes[#notes + 1] = N(high[rnd(#high) + 1], bar * 4 + k / 3, 1 / 3)
        end
        t = 1
      else
        local len = ({ 0.5, 0.5, 0.25, 1, 1, 2 })[rnd(6) + 1]
        if t + len > 4 then len = 4 - t end
        local p = high[rnd(#high) + 1]
        notes[#notes + 1] = N(p, bar * 4 + t, len)
        if rnd(3) == 0 then notes[#notes + 1] = N(p - 3 - rnd(5), bar * 4 + t, len) end
        t = t + len
      end
    end
    for h = 0, 1 do
      local root = 31 + rnd(14)
      notes[#notes + 1] = N(root, bar * 4 + 2 * h, 2)
      if rnd(2) == 0 then notes[#notes + 1] = N(root + 7, bar * 4 + 2 * h, 2) end
    end
  end
  local view, clip = score(notes, 64)
  local marks = view.marks
  local dyn = { "p", "mf", "f", "pp", "ff", "mp" }
  for bar = 0, 15, 2 do
    marks.put(nil, { at = bar * 4, kind = "dyn", value = dyn[bar / 2 % #dyn + 1] })
  end
  marks.put(nil, { at = 1, kind = "cresc", to = 3 })
  marks.put(nil, { at = 10, kind = "dim", to = 18 })
  marks.put(nil, { at = 26, kind = "cresc", to = 40 })
  for bar = 1, 15, 3 do
    marks.slur(nil, bar * 4, bar * 4 + 3.5, 1)
  end
  marks.slur(nil, 37, 46, 1)
  marks.put(nil, { at = 20, kind = "text", value = "dolce" })
  marks.put(nil, { at = 44, kind = "text", value = "a tempo" })
  marks.put(nil, { at = 45, kind = "text", value = "espress." })
  local D = require("notation.doc")
  view:write(function(sc)
    local k = 0
    D.each(sc, function(ev, mi, staff)
      if staff == sc.staves[1].id and ev.kind == "chord" and mi >= 9 and mi <= 10 then
        k = k + 1
        ev.lyric = ({ "Sing", "a", "song", "of", "light" })[(k - 1) % 5 + 1]
      end
    end)
    for mi = 9, 10 do
      D.touch(sc, mi)
    end
  end)
  return view, clip
end

--- What a system's notes and marks cover, column by column, in the
--- system's frame: a skyline for each staff's notes, and one for each mark.
local function system_skies(view, eng, sys)
  local engrave, skyline = require("notation.engrave"), require("notation.skyline")
  local layout = view:layout()
  local width = sys.width + 200
  local notes, marks = {}, {}
  for k = 1, #layout.staves do
    local sky = skyline.new(width)
    for _, placed in ipairs(sys.measures) do
      sky:merge(
        engrave.staff(view.gui.measures, eng.style, placed.m, placed.p, k).sky,
        placed.x,
        sys.staff_top[k] - sys.y
      )
    end
    notes[k] = sky
  end
  for i, item in ipairs(sys.marks) do
    local sky = skyline.new(width)
    sky:shape(item.ink.shape, 0, sys.staff_top[item.staff] - sys.y + item.dy)
    marks[i] = sky
  end
  return notes, marks
end

--- The first column where two skylines' ink overlaps by more than half a
--- pixel, or nil.
local function clash(a, b)
  for x = 0, math.min(a.n, b.n) do
    if math.max(a.top[x], b.top[x]) < math.min(a.bottom[x], b.bottom[x]) - 0.5 then return x end
  end
end

test("notation layout: on a dense score no mark overlaps another, nor the notes of either staff", function()
  local view = dense()
  local eng = paint(view)
  local placed, kinds = 0, {}
  for _, sys in ipairs(eng.systems) do
    local notes, marks = system_skies(view, eng, sys)
    for i, sky in ipairs(marks) do
      local item = sys.marks[i]
      kinds[item.kind] = true
      if item.kind ~= "slur" then
        for k, staff in ipairs(notes) do
          local x = clash(sky, staff)
          if x then
            error(string.format("a %s over the notes of staff %d at x %d (bar %d)", item.kind, k, x, sys.first))
          end
        end
      end
      for j = i + 1, #marks do
        local x = clash(sky, marks[j])
        if x then
          error(string.format("a %s and a %s overlap at x %d (bar %d)", item.kind, sys.marks[j].kind, x, sys.first))
        end
      end
      local _, top, _, bottom = require("notation.skyline").bounds(item.ink.shape)
      local dy = sys.staff_top[item.staff] - sys.y + item.dy
      eq(top + dy >= 0 and bottom + dy <= sys.height, true, "every mark inside its system's band")
    end
    placed = placed + #sys.marks
    for k = 2, #sys.staff_top do
      eq(sys.staff_top[k] > sys.staff_top[k - 1], true)
    end
  end
  eq(placed > 20, true, "many marks were placed")
  for _, kind in ipairs({ "dyn", "cresc", "dim", "text", "slur", "lyric", "number" }) do
    eq(kinds[kind], true, kind .. " placed")
  end
end)

test(
  "notation layout: dynamics and hairpins of a system share one line, and a hairpin stops at the next dynamic",
  function()
    local view = dense()
    local eng = paint(view)
    local rows = 0
    for _, sys in ipairs(eng.systems) do
      local line
      for _, item in ipairs(sys.marks) do
        if (item.kind == "dyn" or item.kind == "cresc" or item.kind == "dim") and item.staff == 1 then
          line = line or item.dy
          eq(item.dy, line, "one line along the system")
          rows = rows + 1
        end
      end
    end
    eq(rows > 8, true)
    -- The diminuendo from beat 10 to 18 meets the f at beat 16: it ends there.
    local found
    for _, sys in ipairs(eng.systems) do
      for _, item in ipairs(sys.marks) do
        if item.kind == "dim" then found = item end
      end
    end
    eq(found and found.to, 16, "ends at the dynamic")
  end
)

test("notation layout: a slur bends over the notes under it, clear of them", function()
  local view = dense()
  local eng = paint(view)
  local slurs = 0
  local engrave = require("notation.engrave")
  local skyline = require("notation.skyline")
  local layout = view:layout()
  for _, sys in ipairs(eng.systems) do
    for _, item in ipairs(sys.marks) do
      if item.kind == "slur" then
        slurs = slurs + 1
        local sl = item.slur
        -- The notes' own skyline of that staff, without marks.
        local sky = skyline.new(sys.width + 100, 0, 4 * eng.style.sp)
        for _, placed in ipairs(sys.measures) do
          local si = engrave.staff(view.gui.measures, eng.style, placed.m, placed.p, item.staff)
          sky:merge(si.sky, placed.x)
        end
        local curve = skyline.new(sys.width + 100)
        curve:shape(item.ink.shape)
        local s = eng.style.sp
        for x = math.ceil(sl.x0 + s), math.floor(sl.x1 - s) do
          if sl.d < 0 then
            eq(
              curve.bottom[x] <= sky.top[x] - 0.15 * s,
              true,
              string.format(
                "the slur passes over the notes at %d: %g against %g (%g,%g to %g,%g bow %g)",
                x,
                curve.bottom[x],
                sky.top[x],
                sl.x0,
                sl.y0,
                sl.x1,
                sl.y1,
                sl.bow
              )
            )
          else
            eq(curve.top[x] >= sky.bottom[x] + 0.15 * s, true, "the slur passes under the notes at " .. x)
          end
        end
      end
    end
  end
  eq(slurs >= 5, true, "the slurs were placed, those over systems in parts")
  local _ = layout
end)

test("notation layout: systems break balanced: none stretched past the bound, no bar alone at the end", function()
  load()
  local breaks = require("notation.breaks")
  local function pre() return 10 end
  -- Filled one at a time these make three bars and one; balanced, two and two.
  local function lines(...) return table.concat(breaks.lines(...), " ") end
  eq(lines({ 30, 30, 30, 30 }, pre, 100), "1 3")
  -- Uneven bars: the stretch is shared out.
  local widths = { 20, 35, 20, 25, 40, 15, 30, 20, 25, 35, 20, 30, 15 }
  local starts = breaks.lines(widths, pre, 100)
  eq(breaks.measure(widths, pre, 100, starts) <= breaks.STRETCH, true, "no line stretched past the bound")
  local last = 0
  for i = starts[#starts], #widths do
    last = last + widths[i]
  end
  eq((10 + last) / 100 >= breaks.LONELY, true, "the last line is not lonely")
  -- What the score asks: a break, a join, a number to a line.
  eq(lines({ 30, 30, 30, 30 }, pre, 100, { breaks = { [2] = true } }), "1 2")
  eq(breaks.lines({ 30, 30, 30, 30 }, pre, 100, { joins = { [3] = true } })[2] ~= 3, true)
  eq(lines({ 10, 10, 10, 10, 10 }, pre, 100, { per = 2 }), "1 3 5")
  -- On the page: every system but the last is spread to the width, by less than the bound.
  local view = dense()
  local eng = paint(view)
  eq(#eng.systems >= 3, true)
  for k, sys in ipairs(eng.systems) do
    local natural = 0
    for _, placed in ipairs(sys.measures) do
      natural = natural + placed.p.natural
    end
    if k < #eng.systems then
      eq((sys.width - sys.x0) / natural - 1 <= breaks.STRETCH + 0.05, true, "system " .. k .. " not over-stretched")
    end
  end
end)

test(
  "notation layout: zs starts a system at the bar, zj keeps one on the system before, kept in the score and undone",
  function()
    local notes = {}
    for bar = 0, 7 do
      for b = 0, 3 do
        notes[#notes + 1] = N(60 + (bar + b) % 8, bar * 4 + b, 1)
      end
    end
    local view, clip = score(notes, 32)
    local function firsts()
      local out = {}
      for _, sys in ipairs(paint(view).systems) do
        out[#out + 1] = sys.first
      end
      return table.concat(out, " ")
    end
    local before = firsts()
    eq(before:find("^1 ") ~= nil, true, before)
    view:set(nil, 9)
    keys("zs")
    local sc = view.score_of(clip:get())
    eq(#sc.layout.breaks, 1)
    local b = sc.layout.breaks[1]
    eq(
      b.kind == "break" and b.measure == sc.measures[3].id and type(b.id) == "string",
      true,
      "a break before bar 3, by its measure's id"
    )
    eq((" " .. firsts() .. " "):find(" 3 ") ~= nil, true, "a system starts at bar 3")
    keys("zs")
    eq(#view.score_of(clip:get()).layout.breaks, 0, "zs again takes it away")
    eq(firsts(), before)
    -- zj on the first bar of a system keeps it on the one before.
    local eng = paint(view)
    local second = eng.systems[2].first
    view:set(nil, (second - 1) * 4)
    keys("zj")
    eq(view.score_of(clip:get()).layout.breaks[1].kind, "join")
    eq((" " .. firsts() .. " "):find(" " .. second .. " ") == nil, true, "no system starts there now")
    api.undo()
    eq(firsts(), before, "undone")
    paw.commands.exec("notation.bars-per-system 2")
    eq(firsts(), "1 3 5 7", "two bars to a system")
    paw.commands.exec("notation.bars-per-system")
    eq(firsts(), before)
    -- The terminal's cell view breaks the same way.
    paw.commands.exec("notation.bars-per-system 3")
    view.first = 1
    view:set(nil, 0)
    api.ui_snapshot(140, 60)
    local systems = view.geometry.systems
    local seen = {}
    for _, sys in ipairs(systems) do
      seen[#seen + 1] = #sys.measures
    end
    eq(
      #systems >= 1 and #systems[1].measures == 3 and (not systems[2] or systems[2].measures[1].m.number == 4),
      true,
      "three bars to a row: " .. table.concat(seen, " ")
    )
  end
)

test("notation layout: a tie into a new system starts after the clef and key, as long as a tie", function()
  local view = score({ N(67, 0, 4), N(69, 4, 8), N(71, 12, 4) }, 16)
  paw.commands.exec("notation.bars-per-system 2")
  local eng = paint(view)
  local sys = eng.systems[2]
  eq(sys.first, 3)
  local engrave = require("notation.engrave")
  local _, spans = engrave.system_ink(eng.style, view:layout(), sys, eng)
  local tie
  for _, op in ipairs(spans.ops) do
    if op[1] == "P" and op[2][2] < sys.x0 then tie = op[2] end
  end
  eq(tie ~= nil, true, "a tie comes in from the system before")
  local s = eng.style.sp
  eq(tie[2] >= sys.signs and tie[2] <= sys.signs + s, true, "it starts just after the clef and key")
  local x1
  for i, v in ipairs(tie) do
    if v == "L" then x1 = tie[i + 1] end
  end
  eq(x1 - tie[2] >= 1.5 * s, true, "and is as long as a tie: " .. (x1 - tie[2]) / s .. " spaces")
end)

test("notation layout: zp lays the systems on pages under the title, and export writes PDF, SVG and PNG", function()
  local view, clip = dense()
  api.project_set("meta", { title = "Dense Study", composer = "A. Tester" })
  keys("zp")
  eq(view.page, true)
  local d = paw.canvas.paint("notation", W, H, { cell = { w = 7.8, h = 17 } })
  local eng = view.gui.engraved
  eq(eng.pages ~= nil and #eng.pages >= 1, true, "pages")
  local title, paper = false, false
  for _, op in ipairs(d.ops) do
    if op[1] == "t" and op[4] == "Dense Study" then title = true end
    if op[1] == "r" and op[6] == "#ffffff" and op[4] == eng.geometry.width then paper = true end
  end
  eq(title and paper, true, "white paper with the title")
  for _, sys in ipairs(eng.systems) do
    local page = eng.pages[sys.page]
    eq(
      sys.y >= page.y + eng.geometry.margin
        and sys.y + sys.height <= page.y + eng.geometry.height - eng.geometry.margin + 1,
      true,
      "each system within its page's margins"
    )
  end
  -- In the run's own scratch: two suites side by side would share one in target/.
  local base = T.scratch .. "/layout-test"
  paw.cmd("notation.export", { base .. ".pdf" })
  local f = io.open(base .. ".pdf", "rb")
  local pdf = f and f:read("*a") or ""
  if f then f:close() end
  eq(pdf:sub(1, 8), "%PDF-1.4")
  eq(
    pdf:find("/Count " .. #require("notation.page").export(view:layout(), base .. ".svg", "svg", { title = "x" }))
      ~= nil,
    true,
    "as many pages in the PDF as SVG files"
  )
  f = io.open(base .. ".svg")
  local svg = f and f:read("*a") or ""
  if f then f:close() end
  eq(svg:find("^<svg") ~= nil and svg:find("</svg>") ~= nil, true)
  paw.cmd("notation.export", { base .. ".png" })
  f = io.open(base .. ".png", "rb")
  eq(f and f:read(4):sub(2, 4), "PNG")
  if f then f:close() end
  os.remove(base .. ".pdf")
  os.remove(base .. ".png")
  for i = 1, 9 do
    os.remove(i == 1 and base .. ".svg" or base .. "-" .. i .. ".svg")
  end
  keys("zp")
  eq(view.page, false)
  local _ = clip
end)

test("notation layout: other features place marks of their own kind against the skylines", function()
  load()
  local skyline = require("notation.skyline")
  skyline.kind("test-chord", {
    order = skyline.ORDER.chord,
    side = "above",
    pad = 0.5,
    row = "test-chords",
    ink = function(out, st, item) out:text(item.x, 0, item.value, st.ink, 14, true) end,
  })
  local view = score({ N(84, 0, 1), N(60, 1, 1), N(88, 2, 2) }, 4)
  local layout = view:layout()
  layout.measures[1].marks = layout.measures[1].marks or {}
  table.insert(layout.measures[1].marks, { at = 0, kind = "test-chord", value = "Cmaj7" })
  table.insert(layout.measures[1].marks, { at = 2, kind = "test-chord", value = "G7" })
  local eng = require("notation.engrave").systems(
    layout,
    require("notation.engrave").style({
      space = 10,
      cell = { w = 1, h = 1 },
      ink = "#000000",
      paper = "#ffffff",
      accent = "#ff0000",
    }),
    { width = 800 }
  )
  local got = {}
  for _, item in ipairs(eng.systems[1].marks) do
    if item.kind == "test-chord" then got[#got + 1] = item end
  end
  eq(#got, 2)
  eq(got[1].dy, got[2].dy, "a row shares one line")
  local top = eng.systems[1].skies[1]
  local _, _, _, bottom = skyline.bounds(got[1].ink.shape)
  eq(bottom + got[1].dy < 0, true, "above the staff, over the high notes")
  skyline.kinds["test-chord"] = nil
  local _ = top
end)
