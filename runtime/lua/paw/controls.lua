-- Controller moves of a MIDI clip, one at a time: the moves of the strip
-- under the piano roll chosen, moved and taken away with the pointer, and
-- drawn as a straight line; and every note and move of a clip as the rows
-- of a list (the event list), each cell changed in place.
--
-- The strip shows one kind of move: `kind` is "bend", "pressure" or "cc"
-- with `number`, moves of the whole channel (not those of one note).
-- Heights in it are fractions, 0 at the bottom; the wheel rests in the
-- middle.
local api = paw.api
local util = paw.util
local music = paw.music
local M = {}

-- The moves chosen with the pointer: places in one clip's list of moves,
-- kept while the clip's moves are what these edits left (as the piano
-- roll keeps its chosen notes).
local chosen = { clip = nil, places = {}, stamp = nil }
paw.seats.keep(
  "controls.chosen",
  function() return chosen end,
  function(c) chosen = c end,
  function() return { clip = nil, places = {}, stamp = nil } end
)

local function stamp_of(clip)
  local ok, data = pcall(api.clip_get, clip)
  return ok and data.control_stamp or nil
end

--- The places of the chosen moves of `clip`, in order.
function M.chosen(clip)
  if chosen.clip ~= clip or chosen.stamp ~= stamp_of(clip) then return {} end
  local out = {}
  for place in pairs(chosen.places) do
    out[#out + 1] = place
  end
  table.sort(out)
  return out
end

local function choose(clip, places)
  local set = {}
  for _, place in ipairs(places) do
    set[place] = true
  end
  chosen = { clip = clip, places = set, stamp = stamp_of(clip) }
  api.ui_redraw()
end

--- True if a move is of the kind of the strip.
function M.is(control, kind, number)
  return control.type == kind and control.key == nil and (kind ~= "cc" or control.number == number)
end

--- A move's value as a height in the strip, and a height as a value.
function M.fraction(kind, value) return kind == "bend" and (value + 1) / 2 or value end
--- A height in the strip, from 0 to 1, as a move's value.
function M.value(kind, fraction)
  fraction = util.clamp(fraction, 0, 1)
  return kind == "bend" and fraction * 2 - 1 or fraction
end

--- A beat on the piano roll's grid, or unless `free` to the nearest of 960
--- ticks a beat.
local function snap(beat, free)
  if free or not paw.opt.note_snap then return math.floor(beat * 960 + 0.5) / 960 end
  return util.round(beat, paw.opt.note_grid)
end

--- Put a clip's moves back, sorted by time as the core keeps them, and
--- choose those of `marked` (moves of the new list, by identity).
local function store(clip, list, marked)
  local order = {}
  for i, control in ipairs(list) do
    order[i] = { control = control, i = i }
  end
  table.sort(order, function(a, b)
    if a.control.start ~= b.control.start then return a.control.start < b.control.start end
    return a.i < b.i
  end)
  local sorted, places = {}, {}
  for i, entry in ipairs(order) do
    sorted[i] = entry.control
    if marked and marked[entry.control] then places[#places + 1] = i end
  end
  paw.clip(clip):set_controls(sorted)
  choose(clip, places)
end

--- Choose one move by its place: `mode` "only", "add" or "toggle".
function M.select(clip, place, mode)
  local set = {}
  if mode == "add" or mode == "toggle" then
    for _, p in ipairs(M.chosen(clip)) do
      set[p] = true
    end
  end
  if mode == "toggle" and set[place] then
    set[place] = nil
  else
    set[place] = true
  end
  local out = {}
  for p in pairs(set) do
    out[#out + 1] = p
  end
  choose(clip, out)
end

--- Choose the moves of the strip's kind that a box touches: from `beat0`
--- to `beat1` and from height `low` to `high`, in any order. `mode` as for
--- `select`. Returns how many are chosen.
function M.select_box(clip, kind, number, beat0, low, beat1, high, mode)
  if beat0 > beat1 then
    beat0, beat1 = beat1, beat0
  end
  if low > high then
    low, high = high, low
  end
  local set = {}
  if mode == "add" or mode == "toggle" then
    for _, p in ipairs(M.chosen(clip)) do
      set[p] = true
    end
  end
  for place, control in ipairs(paw.clip(clip):controls()) do
    local f = M.fraction(kind, control.value)
    if
      M.is(control, kind, number)
      and control.start >= beat0 - 1e-9
      and control.start <= beat1 + 1e-9
      and f >= low - 1e-9
      and f <= high + 1e-9
    then
      if mode == "toggle" and set[place] then
        set[place] = nil
      else
        set[place] = true
      end
    end
  end
  local out = {}
  for p in pairs(set) do
    out[#out + 1] = p
  end
  choose(clip, out)
  return #out
end

--- Choose none of the clip's controller moves.
function M.clear(clip) choose(clip, {}) end

--- Move the selected moves `dbeat` later and `dfraction` of the height of
--- the strip up. The first move goes onto the grid unless `free`. The other
--- moves keep their distance from it. No move leaves the clip or the strip.
function M.move(clip, dbeat, dfraction, free)
  local places = M.chosen(clip)
  if #places == 0 then return 0 end
  local c = paw.clip(clip)
  local list = c:controls()
  local first = list[places[1]]
  local by = snap(first.start + (dbeat or 0), free) - first.start
  for _, place in ipairs(places) do
    by = util.clamp(by, -list[place].start, c.length - 1e-6 - list[place].start)
  end
  local marked = {}
  for _, place in ipairs(places) do
    local control = list[place]
    local kind = control.type
    control.start = control.start + by
    if kind == "bend" or kind == "pressure" or kind == "cc" or kind == "registered" or kind == "assignable" then
      control.value = M.value(kind, M.fraction(kind, control.value) + (dfraction or 0))
    end
    marked[control] = true
  end
  store(clip, list, marked)
  return #places
end

--- Take the chosen moves away. Returns how many went.
function M.remove(clip)
  local places = M.chosen(clip)
  if #places == 0 then return 0 end
  local gone = {}
  for _, place in ipairs(places) do
    gone[place] = true
  end
  local out = {}
  for place, control in ipairs(paw.clip(clip):controls()) do
    if not gone[place] then out[#out + 1] = control end
  end
  store(clip, out)
  return #places
end

--- Draw a straight line of moves of the kind of the strip, from `beat0` at
--- height `f0` to `beat1` at `f1`. It replaces the moves of that kind
--- between them, with one move on each step of the grid (each 32nd of a
--- beat when `free`), with the two ends. The new moves are then selected.
function M.line(clip, kind, number, beat0, f0, beat1, f1, free)
  if beat0 > beat1 then
    beat0, f0, beat1, f1 = beat1, f1, beat0, f0
  end
  local c = paw.clip(clip)
  beat0, beat1 = math.max(0, snap(beat0, free)), math.min(c.length - 1e-6, snap(beat1, free))
  if beat1 < beat0 then return 0 end
  local out = {}
  for _, control in ipairs(c:controls()) do
    if not (M.is(control, kind, number) and control.start >= beat0 - 1e-9 and control.start <= beat1 + 1e-9) then
      out[#out + 1] = control
    end
  end
  local step = (free or not paw.opt.note_snap) and 1 / 32 or paw.opt.note_grid
  local steps = math.max(0, math.floor((beat1 - beat0) / step + 1e-6))
  local marked, made = {}, 0
  local function add(beat)
    local t = beat1 > beat0 and (beat - beat0) / (beat1 - beat0) or 1
    local control =
      { start = beat, type = kind, number = kind == "cc" and number or nil, value = M.value(kind, f0 + (f1 - f0) * t) }
    out[#out + 1], marked[control], made = control, true, made + 1
  end
  for i = 0, steps do
    add(beat0 + i * step)
  end
  -- The far end, where it falls between steps.
  if beat1 - (beat0 + steps * step) > 1e-6 then add(beat1) end
  store(clip, out, marked)
  return made
end

-- The event list.

--- What the list's columns hold.
M.columns = { "time", "kind", "which", "value", "length" }

--- Every note and move of a clip, in time order, as rows of the list: a
--- note `{ kind = "note", place, start, note }`, a move `{ kind = "control",
--- place, start, control }`. Notes come before moves at the same time.
--- Notes and moves hidden by a trim of the clip's edges are left out.
function M.rows(clip)
  local c = paw.clip(clip)
  local length = c.length
  local rows = {}
  for place, n in ipairs(c:notes()) do
    if n.start >= 0 and n.start < length then
      rows[#rows + 1] = { kind = "note", place = place, start = n.start, note = n }
    end
  end
  for place, control in ipairs(c:controls()) do
    if control.start >= 0 and control.start < length then
      rows[#rows + 1] = { kind = "control", place = place, start = control.start, control = control }
    end
  end
  table.sort(rows, function(a, b)
    if math.abs(a.start - b.start) > 1e-9 then return a.start < b.start end
    if a.kind ~= b.kind then return a.kind == "note" end
    return a.place < b.place
  end)
  return rows
end

local function trim(x)
  local text = string.format("%.2f", x):gsub("0+$", ""):gsub("%.$", "")
  return text
end

--- A move's value in the units the list shows it in: seven-bit steps (with
--- the finer part as decimals) for controllers and pressure, -8192 to 8191
--- for the pitch wheel, semitones for a note's own bend, the number of a
--- program.
local function shown_value(control)
  if control.type == "program" then return tostring(control.program) end
  if control.type == "bend" and control.key then return string.format("%+.2f st", control.value * 48) end
  if control.type == "bend" then return trim(control.value * 8192) end
  return trim(control.value * 127)
end

--- The text of each column of a row, by the names in `M.columns`.
function M.cells(clip, row)
  local c = api.clip_get(clip)
  local time = paw.time.format(c.start + row.start)
  if row.kind == "note" then
    local n = row.note
    return {
      time = time,
      kind = "note",
      which = music.name(n.pitch),
      value = tostring(n.velocity),
      length = trim(n.length),
    }
  end
  local m = row.control
  local which = ""
  if m.type == "cc" then
    which = tostring(m.number)
  elseif m.type == "registered" or m.type == "assignable" then
    which = m.key and tostring(m.index) or (m.bank or 0) .. ":" .. m.index
  elseif m.type == "program" and m.bank then
    which = "bank " .. m.bank
  end
  if m.key then which = music.name(m.key) .. (which ~= "" and " " .. which or "") end
  return { time = time, kind = m.type, which = which, value = shown_value(m), length = "" }
end

--- A time as the list writes it, `bar.beat.hundredths` (or `bar.beat`, or
--- `bar`), as beats from the clip's start.
local function parse_time(clip, text)
  local bar, beat, part = text:match("^%s*(%d+)%.?(%d*)%.?(%d*)%s*$")
  if not bar then error("a time is bar.beat.hundredths, like 3.2.50", 0) end
  local at = paw.time.bar_start(tonumber(bar))
  local _, den = api.tempo_signature(at)
  local unit = 4 / (den or 4)
  at = at + ((tonumber(beat) or 1) - 1 + (tonumber(part) or 0) / 100) * unit
  return at - api.clip_get(clip).start
end

local function number(text, what)
  local value = tonumber((text:gsub("st%s*$", ""):gsub("^%s*%+?", ""):gsub("%s+$", "")))
  if not value then error(what, 0) end
  return value
end

--- Change one cell of a row from text written as the list shows it.
--- Errors say what is wrong.
function M.edit(clip, row, column, text)
  local c = paw.clip(clip)
  text = tostring(text)
  if column == "kind" then error("a row's kind stays; delete it and add another", 0) end
  if row.kind == "note" then
    local change = {}
    if column == "time" then
      change.start = parse_time(clip, text)
      if change.start < 0 or change.start >= c.length then error("that time is outside the clip", 0) end
    elseif column == "which" then
      local ok, pitch = pcall(music.pitch, tonumber(text) or text:gsub("%s", ""))
      if not ok or pitch < 0 or pitch > 127 then error("a pitch is a name like E4 or a number to 127", 0) end
      change.pitch = pitch
    elseif column == "value" then
      change.velocity = util.clamp(math.floor(number(text, "a velocity is 1 to 127") + 0.5), 1, 127)
    elseif column == "length" then
      change.length = number(text, "a length is a number of beats")
      if change.length <= 0 then error("a length is above 0", 0) end
    end
    c:set_note(row.place, change)
    return
  end
  local list = c:controls()
  local m = list[row.place]
  if column == "time" then
    m.start = parse_time(clip, text)
    if m.start < 0 or m.start >= c.length then error("that time is outside the clip", 0) end
  elseif column == "length" then
    error("a controller move has no length", 0)
  elseif column == "value" then
    local v = number(text, "a value is a number")
    if m.type == "program" then
      m.program = util.clamp(math.floor(v + 0.5), 0, 127)
    elseif m.type == "bend" and m.key then
      m.value = util.clamp(v / 48, -1, 1)
    elseif m.type == "bend" then
      m.value = util.clamp(v / 8192, -1, 1)
    else
      m.value = util.clamp(v / 127, 0, 1)
    end
  elseif column == "which" then
    -- A note's name first makes it the move of that note.
    local key, rest = text:match("^%s*([A-Ga-g][#b]?%-?%d+)%s*(.-)%s*$")
    if key then
      m.key = music.pitch(key)
    else
      rest = text
    end
    if m.type == "cc" then
      local n = tonumber(rest)
      if not n or n < 0 or n > 127 then error("a control change is numbered 0 to 127", 0) end
      m.number = math.floor(n)
    elseif m.type == "registered" or m.type == "assignable" then
      local bank, index = rest:match("^(%d+):(%d+)$")
      index = tonumber(index or rest)
      if not index then error("a registered or assignable controller is bank:index", 0) end
      m.bank, m.index = tonumber(bank) or m.bank, math.floor(index)
    end
  end
  c:set_controls(list)
end

--- Take a row away.
function M.remove_row(clip, row)
  local c = paw.clip(clip)
  if row.kind == "note" then return c:remove_note(row.place) end
  local list = c:controls()
  table.remove(list, row.place)
  c:set_controls(list)
end

--- Add a move at `start` beats into the clip: of `kind` ("cc" with
--- `number`, "bend", "pressure", "program"), at rest or 0. Returns it.
function M.add(clip, start, kind, number)
  local c = paw.clip(clip)
  local control = { start = start, type = kind }
  if kind == "cc" then
    control.number, control.value = number or 1, 0
  end
  if kind == "bend" or kind == "pressure" then control.value = 0 end
  if kind == "program" then
    control.program, control.value = 0, 0
  end
  local list = c:controls()
  list[#list + 1] = control
  c:set_controls(list)
  return control
end

return M
