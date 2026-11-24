-- Tests of what using notation as a composer turned up: a played note on
-- the grid by chance, hairpins over barlines in the cell view, the popover
-- clear of what it previews, `K` on a note. Loaded by tests/suite.lua.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local paw = require("paw")
local api = paw.api

local function load()
  if not package.loaded["notation.keys"] then paw.ext.load("extensions/notation") end
  return require("notation"), require("notation.model")
end

local function N(pitch, start, length, velocity)
  return { pitch = pitch, start = start, length = length, velocity = velocity or 80 }
end

local keys = T.keys

--- A part with a clip open as notation.
local function song(notes, length)
  fresh()
  local view = load()
  local part = paw.add_part({ name = "Lead" })
  part:add_device("synth")
  local clip = part:add_clip({ start = 0, length = length or 8, name = "tune", notes = notes or {} })
  paw.flush()
  paw.keymap.set_mode("n")
  view:edit(clip)
  view.value, view.dot, view.voice, view.triplets, view.tuplet = 1, false, 1, false, nil
  api.undo_checkpoint()
  return view, clip, part
end

local function screen(w, h) return table.concat(api.ui_snapshot(w or 160, h or 50), "\n") end

test("notation: a played note that lands on the grid by chance is read as played, a drawn one as drawn", function()
  local _, model = load()
  -- From a MIDI file at 480 ticks a beat: the E5 starts on beat four and
  -- is let go 400 ticks later, five sixths of a beat, among notes that are
  -- off the grid.
  local played = {
    N(72, 0.0042, 0.8292),
    N(74, 1, 0.3937),
    N(76, 1.5229, 0.3771),
    N(77, 2.0292, 0.7833),
    N(76, 3, 0.8333),
    N(74, 4.0417, 0.4896),
    N(72, 4.4667, 0.3854),
  }
  eq(
    model.text(model.layout(played, { length = 8 })),
    "q C5 e D5 e E5 q F5 q E5 | e D5 e C5 qr hr",
    "a quarter, not a sextuplet"
  )
  eq(
    model.text(model.layout({ N(60, 0, 5 / 6), N(62, 1, 1) }, { length = 4 })),
    "6{q~ C4 s C4 sr} q D4 hr",
    "notes drawn on the grid are written as they are"
  )
  local entered = N(76, 3, 5 / 6)
  entered.meta = { notation = { letter = 2, alter = 0, pitch = 76 } }
  played[5] = entered
  eq(
    model.text(model.layout(played, { length = 8 })):match("^[^|]*"),
    "q C5 e D5 e E5 q F5 6{q~ E5 s E5 sr} ",
    "and so is a note notation wrote, among played ones"
  )
end)

--- A row of the screen as its characters, one a cell.
local function cells(row)
  local out = {}
  for ch in row:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    out[#out + 1] = ch
  end
  return out
end

--- Eight quarter notes over two bars, C D E F G A B C.
local function scale()
  local notes = {}
  for i, p in ipairs({ 72, 74, 76, 77, 79, 81, 83, 84 }) do
    notes[i] = N(p, i - 1, 1)
  end
  return notes
end

test("notation: in the cell view a hairpin runs on over the barline to where it ends", function()
  local view = song(scale())
  view:set(nil, 0)
  keys("v6l<localleader>d<lt>f<CR>")
  local rows = api.ui_snapshot(160, 50)
  local pin, bottom
  for i, row in ipairs(rows) do
    if row:find("<─", 1, true) then pin = i end
    if row:find("└", 1, true) and not bottom then bottom = i end
  end
  eq(pin ~= nil and bottom ~= nil, true, "a hairpin under the staff:\n" .. table.concat(rows, "\n"))
  local line, under = cells(rows[bottom]), cells(rows[pin])
  local barline
  for x, ch in ipairs(line) do
    if ch == "┴" and not barline then barline = x end
  end
  eq(under[barline + 2], "─", "past the barline between bars one and two:\n" .. rows[bottom] .. "\n" .. rows[pin])
  local f = rows[pin]:find("f", 1, true)
  eq(f ~= nil, true, "and the dynamic it reaches after it")
end)

test("notation: a dynamic's popover opens under the row it previews on", function()
  local view = song(scale())
  view:set(nil, 1)
  keys("<localleader>dff")
  local rows = api.ui_snapshot(160, 50)
  local prompt, ghost
  for i, row in ipairs(rows) do
    if row:find("dynamic ff", 1, true) then
      prompt = i
    elseif row:find("ff", 1, true) and not ghost then
      ghost = i
    end
  end
  keys("<Esc>")
  eq(prompt ~= nil, true, "the prompt is open")
  eq(
    ghost ~= nil and ghost < prompt,
    true,
    "the ff it would write is drawn, above the prompt:\n" .. table.concat(rows, "\n")
  )
end)

test("notation: K on a note says how it is written and what MIDI note it is", function()
  local view = song(scale())
  keys("<localleader>dmf<CR>")
  local _, model = load()
  for _, ev in ipairs(model.events(view:layout())) do
    if ev.start == 1 then view:set(ev.notes[1].step, 1) end
  end
  keys("g'")
  keys("K")
  local text = T.hover_text()
  keys("<Esc>")
  eq(text:find("Note  D5", 1, true) ~= nil, true, "the note's name:\n" .. text)
  eq(
    text:find("written quarter, voice 1, staccato, under mf", 1, true) ~= nil,
    true,
    "its value, voice, marks and dynamic:\n" .. text
  )
  eq(
    text:find("played at 1.2.00, 0.5 beats long, velocity 80 (MIDI note 74", 1, true) ~= nil,
    true,
    "the MIDI note:\n" .. text
  )
  eq(text:find("Clip  tune", 1, true) ~= nil, true, "then the clip and part, as everywhere")
end)

test("notation: in insert mode the title keeps the key and metre beside the INS badge", function()
  song(scale())
  keys("i")
  local rows = api.ui_snapshot(160, 50)
  keys("<Esc>")
  local title
  for _, row in ipairs(rows) do
    if row:find(" INS ", 1, true) then title = row end
  end
  eq(title ~= nil, true, "the badge is drawn")
  eq(title:find("C major  4/4", 1, true) ~= nil, true, "the key and metre whole: " .. tostring(title))
  eq(
    title:find("quarter", 1, true) == title:find("INS quarter", 1, true) + 4,
    true,
    "the value once, in the badge: " .. title
  )
end)

test("notation: the title names a song in A minor so, not C major, with no key set", function()
  local function title()
    for _, row in ipairs(api.ui_snapshot(160, 50)) do
      if row:find("4/4", 1, true) and row:find("tune", 1, true) then return row end
    end
  end
  -- A minor: the tonic chord first and last, the leading tone G sharp before it.
  song({ N(57, 0, 1), N(60, 1, 1), N(64, 2, 1), N(69, 3, 1), N(64, 4, 1), N(68, 5, 1), N(71, 6, 1), N(69, 7, 1) })
  local row = title()
  eq(row and row:find("A minor  4/4", 1, true) ~= nil, true, "the minor key the music is in: " .. tostring(row))
  song(scale())
  row = title()
  eq(row and row:find("C major  4/4", 1, true) ~= nil, true, "and C major for music in C: " .. tostring(row))
end)

test("notation: in the cell view a low second voice's stems stop at their system, clear of the next", function()
  -- Whole notes over quarters: the only stems are the low voice's.
  local notes = {}
  for i = 0, 15 do
    if i % 4 == 0 then notes[#notes + 1] = N(72, i, 4) end
    local low = N(55 - (i % 3), i, 1)
    low.meta = { notation = { voice = 2 } }
    notes[#notes + 1] = low
  end
  song(notes, 16)
  paw.cmd("notation.clef", { "treble" })
  local rows = api.ui_snapshot(80, 100)
  local numbers
  for i, row in ipairs(rows) do
    -- The second system's bar numbers: a row that starts with a number past 1.
    local first = row:match("^%s+(%d+)%s")
    if first and tonumber(first) > 1 and not numbers then numbers = i end
  end
  eq(numbers ~= nil, true, "two systems:\n" .. table.concat(rows, "\n"))
  eq(
    rows[numbers]:find("│", 1, true),
    nil,
    "nothing of the system above on its bar numbers:\n" .. table.concat(rows, "\n", math.max(1, numbers - 12), numbers)
  )
end)

test("notation: a dynamic written inside a hairpin ends its ramp there, as it is drawn", function()
  local view, clip = song(scale())
  view:set(nil, 0)
  keys("v6l<localleader>dp<lt>f<CR>")
  local function velocities()
    local out = {}
    for i, n in ipairs(clip:notes()) do
      out[i] = n.velocity
    end
    return out
  end
  local v = velocities()
  eq(v[1] < v[2] and v[2] < v[3] and v[3] < v[4], true, "a ramp from p: " .. table.concat(v, " "))
  view:set(nil, 3)
  keys("<localleader>dmf<CR>")
  v = velocities()
  eq(v[4], 80, "the note at the mf plays mf: " .. table.concat(v, " "))
  eq(v[5], 80, "and so does the next, the hairpin over: " .. table.concat(v, " "))
  eq(v[2] < v[3] and v[3] < 80, true, "the ramp before rises to mf: " .. table.concat(v, " "))
end)

test("notation: :notation.set alone lists every setting on a page, saying which the clip changed", function()
  song(scale())
  paw.cmd("notation.set", { "swing", "off" })
  keys(":notation.set<CR>")
  local text = screen(160, 50)
  keys("q")
  for _, k in ipairs(require("notation.score").ORDER) do
    eq(text:find("  " .. k .. " ", 1, true) ~= nil, true, k .. " is listed:\n" .. text)
  end
  eq(
    text:find("swing       off       (default auto)", 1, true) ~= nil,
    true,
    "a setting changed says its default:\n" .. text
  )
  eq(
    text:find("chord       35       ", 1, true) ~= nil and text:find("(default 35)", 1, true) == nil,
    true,
    "one left alone, its value"
  )
end)
