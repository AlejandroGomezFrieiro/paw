-- Tests of the vertical zoom (paw/vzoom.tl): Ctrl-= Ctrl-- Ctrl-0 and
-- z+ z- z= make the rows of the view under the cursor taller or shorter,
-- as view state of each window: never an undo step, kept in the
-- project's screen. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api
local L = paw.layout
local keys = T.keys
local roll = paw.ui.views:get("pianoroll")

local W, H = 120, 40
local initial = L.capture()

local function reset()
  paw.keymap.feed("<Esc><Esc>")
  L.restore(initial)
  paw.ui.focus("arrange")
end

--- Four tracks, the cursor on the first, the arrange view drawn.
local function band()
  fresh()
  reset()
  T.after(reset)
  local out = {}
  for i, name in ipairs({ "Drums", "Bass", "Keys", "Pad" }) do
    out[i] = paw.add_track({ name = name }).id
  end
  paw.flush()
  api.undo_checkpoint()
  paw.cursor.set_track(out[1])
  return out
end

--- The rows each track takes in the arrange view, by id, drawn again.
local function heights()
  api.ui_snapshot(W, H)
  local out = {}
  for _, row in ipairs(paw.ui.views:get("arrange").geometry.layout.rows) do
    if row.kind == "track" then out[row.id] = row.h end
  end
  return out
end

test("Ctrl-= makes every track taller and Ctrl-0 fits them again; on a selection only those tracks", function()
  local ids = band()
  local edits = api.project_get().edits
  local th = heights()[ids[1]]
  keys("<C-=>")
  local h = heights()
  for _, id in ipairs(ids) do
    eq(h[id], th + 1, "every track a row taller")
  end
  eq(paw.opt.track_height, "auto", "the option is as it was: the window has the zoom")
  keys("<C-0>")
  eq(heights()[ids[1]], th, "Ctrl-0: the tracks fit the window again")
  keys("jVj<C-=>")
  h = heights()
  eq(
    table.concat({ h[ids[1]], h[ids[2]], h[ids[3]], h[ids[4]] }, " "),
    table.concat({ th, th + 1, th + 1, th }, " "),
    "Bass and Keys only"
  )
  eq(paw.keymap.mode, "n", "the selection ends")
  eq(api.project_get().edits, edits, "no edit of the project: no undo step")
end)

test("z+ z- z= are the same keys for terminals that do not send Ctrl-=", function()
  local ids = band()
  local th = heights()[ids[1]]
  keys("z+z+")
  eq(heights()[ids[1]], th + 2, "z+ twice")
  keys("z-")
  eq(heights()[ids[1]], th + 1, "z-")
  keys("z=")
  eq(heights()[ids[1]], th, "z=")
end)

test("the zoom is the window's: a split starts with it, and the project's screen keeps it", function()
  local ids = band()
  local th = heights()[ids[1]]
  keys("<C-=><C-=>")
  keys(":vs<CR>")
  eq(L.current().vzoom.track_rows, th + 2, "the split has it")
  keys("<C-->")
  eq(L.current().vzoom.track_rows, th + 1, "and changes its own")
  local path = T.scratch .. "/vzoom-project"
  keys(":w " .. path .. "<CR>")
  L.restore(initial)
  keys(":e " .. path .. "<CR>")
  local rows = {}
  for _, win in ipairs(L.windows(paw.ui.layout)) do
    if win.view == "arrange" then rows[#rows + 1] = win.vzoom and win.vzoom.track_rows end
  end
  table.sort(rows)
  eq(table.concat(rows, " "), (th + 1) .. " " .. (th + 2), "each window's zoom comes back with the project")
end)

test("in the piano roll Ctrl-= gives two rows to a key: the note fills both, the cursor moves by key", function()
  fresh()
  reset()
  T.after(function()
    paw.ui.hide("pianoroll")
    reset()
  end)
  local t = paw.add_track({ name = "keys" })
  local clip = t:add_clip({ name = "riff", start = 0, length = 8, notes = { { pitch = 60, start = 0, length = 2 } } })
  roll:edit(clip)
  roll.top, roll.scroll, roll.pitch, roll.beat = 72, 0, 60, 0
  local function cell(beat, line)
    local shot = api.ui_view_snapshot("pianoroll", 100, 30)
    local g = roll.geometry
    local x = g.keys + math.floor((beat - roll.scroll) * g.zoom + 0.5)
    for _, run in ipairs(shot.rows[g.head + line + 1] or {}) do
      if x >= run.x and x < run.x + run.w then return run.bg end
    end
  end
  keys("<C-=>")
  api.ui_view_snapshot("pianoroll", 100, 30)
  eq(roll.geometry.per, 2, "two rows a key")
  local first = (roll.top - 60) * 2
  local note = cell(1, first)
  eq(cell(1, first + 1), note, "the note on its second row too")
  eq(cell(1, first + 2) ~= note, true, "and not on the key below")
  eq(cell(5, first + 1) ~= note, true, "nor past its end")
  keys("k")
  eq(roll.pitch, 61, "k goes up a key, not a row")
  keys("<C-0>")
  api.ui_view_snapshot("pianoroll", 100, 30)
  eq(roll.geometry.per, 1, "Ctrl-0: one row a key")
end)
