-- Tests of folds (paw/folds.tl): view state of each window, as Vim's,
-- never an undo step, kept in the project's screen. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api
local L = paw.layout
local keys = T.keys

local initial = L.capture()

local function reset()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  L.restore(initial)
  paw.ui.focus("arrange")
end

local function start()
  fresh()
  reset()
  T.after(reset)
end

local function names(ids)
  local out = {}
  for i, id in ipairs(ids) do
    out[i] = api.track_get(id).name
  end
  return table.concat(out, " ")
end

--- Drums, a group Strings (Violins, Cellos), Bass, Keys and Pad.
local function band()
  local drums = paw.add_track({ name = "Drums" })
  local violins, cellos = paw.add_track({ name = "Violins" }), paw.add_track({ name = "Cellos" })
  local bass, keys_, pad =
    paw.add_track({ name = "Bass" }), paw.add_track({ name = "Keys" }), paw.add_track({ name = "Pad" })
  local strings = paw.groups.make({ violins, cellos }, "Strings")
  paw.flush()
  api.undo_checkpoint()
  return { drums = drums, strings = strings, violins = violins, cellos = cellos, bass = bass, keys = keys_, pad = pad }
end

--- The arrange view's scene of a window, as the graphical window gets it.
local function scene(win)
  paw.ui.render_scene("arrange", 120, 30, { w = 8, h = 16 }, win)
  local patch = api.scene_end(0, "folds" .. win.id) or ""
  api.scene_forget(0)
  return patch
end

test("za folds a group in one window only, makes no undo step, and the window's scene draws it", function()
  start()
  local b = band()
  local edits = api.project_get().edits
  local left = L.current()
  keys(":vs<CR>")
  local right = L.current()
  eq(right ~= left, true, "a second window")
  paw.cursor.set_track(b.strings)
  keys("za")
  eq(names(paw.groups.rows()), "Drums Strings Bass Keys Pad", "folded in this window")
  eq(paw.folds.group_closed(b.strings.id, left), false, "the other window shows the group open")
  eq(api.project_get().edits, edits, "no edit of the project: the undo tree is as it was")
  eq(scene(right):find("Strings +2", 1, true) ~= nil, true, "the folded window's scene draws the fold")
  eq(scene(left):find("Violins", 1, true) ~= nil, true, "the other's draws the members")
end)

test("a fold of a group comes back with the project, in its window; the group keeps no fold", function()
  start()
  local b = band()
  paw.cursor.set_track(b.violins)
  keys("za")
  eq(names(paw.groups.rows()), "Drums Strings Bass Keys Pad", "za on a member folds its group")
  local path = T.scratch .. "/folds-project"
  keys(":w " .. path .. "<CR>")
  L.restore(initial)
  keys(":e " .. path .. "<CR>")
  eq(names(paw.groups.rows()), "Drums Strings Bass Keys Pad", "folded again when opened")
  local strings = paw.scope.named("Strings").id
  eq(api.track_get(strings).meta.group_folded, nil, "nothing about the fold in the group's meta")
  keys("zR")
  eq(#paw.groups.rows(), 7, "zR opens it")
end)

test("Vjjzf folds three tracks into a row named Fold 1; zd deletes the fold, zE every fold", function()
  start()
  local b = band()
  paw.cursor.set_track(b.bass)
  keys("Vjjzf")
  eq(names(paw.groups.rows()), "Drums Strings Violins Cellos Bass", "one row for the three")
  eq(paw.cursor.track_id(), b.bass.id, "the cursor on the fold's row")
  local text = table.concat(api.ui_snapshot(120, 30), "\n")
  eq(text:find("Fold 1 +3", 1, true) ~= nil, true, "the row has the fold's name:\n" .. text)
  keys("za")
  eq(#paw.groups.rows(), 7, "za opens it")
  keys("za")
  eq(#paw.groups.rows(), 5, "and folds it again")
  keys("zd")
  eq(names(paw.groups.rows()), "Drums Strings Violins Cellos Bass Keys Pad", "zd: the fold is gone")
  eq(#api.track_list(), 7, "and every track is there")
  paw.cursor.set_track(b.drums)
  keys("Vjzf")
  paw.cursor.set_track(b.bass)
  keys("Vjzf")
  eq(#paw.groups.rows(), 5, "two folds")
  keys("zE")
  eq(#paw.groups.rows(), 7, "zE deletes them both")
  eq(#api.track_list(), 7, "the tracks stay")
end)

test("znn on a fold enters it, and zw comes back with the fold closed", function()
  start()
  local b = band()
  paw.cursor.set_track(b.bass)
  keys("Vjjzf")
  keys("znn")
  eq(paw.scope.breadcrumb(), "Song › Fold 1", "znn enters the fold")
  eq(names(paw.groups.rows()), "Bass Keys Pad", "its tracks, open")
  keys("j")
  keys("zw")
  eq(paw.scope.current(), nil, "zw: the song again")
  eq(names(paw.groups.rows()), "Drums Strings Violins Cellos Bass", "the fold is closed as it was")
  eq(paw.cursor.track_id(), b.bass.id, "the cursor on its row")
end)

test("K on a folded group: its name, its tracks, and that it is folded", function()
  start()
  local b = band()
  paw.cursor.set_track(b.strings)
  keys("za")
  keys("K")
  local text = T.hover_text()
  eq(text:find("Fold  Strings\n  Song › Strings · 3 tracks · folded", 1, true) ~= nil, true, text)
end)

test("<Space>zz lists the window's folds, marked fold, with the path; choosing one enters it", function()
  start()
  local b = band()
  paw.cursor.set_track(b.bass)
  keys("Vjjzf")
  keys("<Space>zz")
  keys("Fold")
  local text = table.concat(api.ui_snapshot(160, 40), "\n")
  eq(text:find("fold%s+Fold 1") ~= nil, true, "marked fold:\n" .. text)
  eq(text:find("│ Song › Fold 1%s") ~= nil, true, "the path in the preview:\n" .. text)
  eq(text:find("│ 3 tracks · folded%s") ~= nil, true, "and what it holds:\n" .. text)
  keys("<CR>")
  eq(paw.scope.breadcrumb(), "Song › Fold 1", "entered")
  eq(names(paw.groups.rows()), "Bass Keys Pad", "its tracks")
end)

-- Time folds -------------------------------------------------------------------------------

local W, H = 160, 40
local function screen() return table.concat(api.ui_snapshot(W, H), "\n") end

--- Two tracks with a synth and a clip of 16 bars each, in 4/4, a region
--- Bridge over bars 5 to 12 (beats 16 to 48), and the cursor on the first
--- track. A column a beat, the grid a beat.
local function song()
  start()
  api.engine_restart({ backend = "null" })
  local saved = { zoom = paw.opt.zoom, grid = paw.opt.grid }
  T.after(function()
    paw.opt.zoom, paw.opt.grid = saved.zoom, saved.grid
  end)
  paw.opt.zoom, paw.opt.grid = 1, 1
  paw.ui.views:get("arrange").scroll = 0
  for i, name in ipairs({ "Keys", "Bass" }) do
    local t = paw.add_track({ name = name })
    t:add_device("synth", { attack = 0.001, release = 0.05 })
    local notes = {}
    for beat = 0, 62, 2 do
      notes[#notes + 1] = { pitch = 40 + 12 * i + beat % 7, start = beat, length = 1 }
    end
    t:add_clip({ name = name .. " part", start = 0, length = 64, notes = notes })
    if i == 1 then paw.cursor.set_track(t) end
  end
  paw.markers.add(16, "Bridge", { length = 32 })
  paw.flush()
  api.undo_checkpoint()
end

--- A render of the song, as bytes.
local function render(name)
  local path = T.scratch .. "/" .. name .. ".wav"
  paw.render(path, { bits = 32, tail = 1 })
  local f = assert(io.open(path, "rb"))
  local bytes = f:read("*a")
  f:close()
  return bytes
end

test("zfar folds a region into one column 'Bridge ▸ 8'; l takes it as one step; a render is the same", function()
  song()
  local open = render("folds-open")
  local edits = api.project_get().edits
  paw.cursor.set_beat(20)
  keys("zfar")
  eq(paw.cursor.beat, 16, "the cursor on the fold's column")
  local text = screen()
  eq(text:find("Bridge ▸ 8", 1, true) ~= nil, true, "one column with the name and the bars:\n" .. text)
  local view = paw.ui.views:get("arrange")
  eq(view:col(48) - view:col(16) < 32, true, "the bars after it move left: 8 bars in a narrow column")
  paw.cursor.set_beat(15)
  keys("l")
  eq(paw.cursor.beat, 16, "l onto the fold")
  local lines = api.ui_snapshot(W, H)
  local bottom = lines[#lines - 1] .. "\n" .. lines[#lines]
  eq(bottom:find("Bridge ▸ 8", 1, true) ~= nil, true, "the status line names it:\n" .. bottom)
  keys("l")
  eq(paw.cursor.beat, 48, "l again: past the fold in one step")
  keys("h")
  eq(paw.cursor.beat, 16, "h: back onto it")
  paw.cursor.set_beat(60)
  view.scroll = 12
  keys("zl")
  keys("zl")
  eq(view.scroll, 48, "zl scrolls past the fold in one step")
  eq(api.project_get().edits, edits, "no edit of the project")
  eq(render("folds-closed") == open, true, "a render with the fold is the same, bit for bit")
end)

test("zm closes the deepest level of regions first, a second zm the next; zr opens one again", function()
  song()
  paw.markers.remove(paw.markers.find("Bridge"))
  paw.markers.add(0, "Chorus 2", { length = 32 })
  paw.markers.add(0, "Verse A", { length = 16 })
  paw.markers.add(16, "Verse B", { length = 16 })
  paw.flush()
  local function folded()
    local out = {}
    for _, s in ipairs(paw.folds.time_spans()) do
      out[#out + 1] = s.label
    end
    return table.concat(out, ", ")
  end
  keys("zm")
  eq(folded(), "Verse A ▸ 4, Verse B ▸ 4", "zm closes Verse A and Verse B")
  keys("zm")
  eq(folded(), "Chorus 2 ▸ 8", "a second zm closes Chorus 2")
  eq(screen():find("Chorus 2 ▸ 8", 1, true) ~= nil, true, "drawn")
  keys("zr")
  eq(folded(), "Verse A ▸ 4, Verse B ▸ 4", "zr opens Chorus 2 again")
  keys("zR")
  eq(folded(), "", "zR opens every level")
end)

test("znn on a folded column enters the region; zw comes back with it closed", function()
  song()
  paw.cursor.set_beat(20)
  keys("zfar")
  keys("znn")
  eq(paw.scope.breadcrumb(), "Song › Bridge", "znn enters the region")
  eq(#paw.folds.time_spans(), 0, "open inside it")
  keys("zw")
  eq(paw.scope.current(), nil, "zw: the song")
  eq(paw.folds.time_spans()[1].label, "Bridge ▸ 8", "the fold closed as it was")
  keys("zd")
  eq(#paw.folds.time_spans(), 0, "zd deletes it")
end)

-- Block folds ------------------------------------------------------------------------------

--- Keys, Bass and Pad with a clip of 16 bars each (as `song`, without a
--- region), and the cursor on Keys at bar 5.
local function trio()
  song()
  paw.markers.remove(paw.markers.find("Bridge"))
  local pad = paw.add_track({ name = "Pad" })
  pad:add_device("synth", { attack = 0.001, release = 0.05 })
  pad:add_clip({ name = "Pad part", start = 0, length = 64, notes = { { pitch = 60, start = 0, length = 64 } } })
  paw.flush()
  api.undo_checkpoint()
  paw.cursor.set_beat(16)
end

--- The lines of the screen that a track's rows take: from its header to
--- the next track's header, or to the master.
local function rows_of(text, name, next_name)
  local from = text:find("\n[^\n]*" .. name)
  local to = text:find("\n[^\n]*" .. (next_name or "master"), from + 1)
  return text:sub(from, to)
end

test("a visual block over two tracks and four bars, then zf, draws one cell; the other track shows its clip", function()
  trio()
  local open = render("block-open")
  local edits = api.project_get().edits
  local before = screen()
  keys("<C-v>j16lzf")
  local f = paw.folds.list()[1]
  eq({ f.kind, #f.tracks, f.from, f.to, f.closed }, { "range", 2, 16, 32, true }, "a closed block of two tracks")
  local text = screen()
  local keys_rows = rows_of(text, "Keys", "Bass")
  eq(keys_rows:find("Fold 1", 1, true) ~= nil, true, "one cell with the name:\n" .. keys_rows)
  eq(rows_of(text, "Pad", "new track"), rows_of(before, "Pad", "new track"), "Pad shows its clip there as before")
  eq(scene(L.current()):find("Fold 1", 1, true) ~= nil, true, "the scene of the window carries the cell")
  eq(#paw.folds.time_spans(), 0, "no column: the time of the other tracks stays")
  eq(render("block-closed") == open, true, "a render with the fold is the same, bit for bit")
  eq(api.project_get().edits, edits, "no edit of the project")

  keys("za")
  eq(rows_of(screen(), "Keys", "Bass"), rows_of(before, "Keys", "Bass"), "za opens it: the clips again")
  keys("za")
  keys("znn")
  eq(paw.scope.breadcrumb(), "Song › Fold 1", "znn enters it")
  eq(#paw.folds.blocks(), 0, "open inside it")
  keys("zw")
  eq(rows_of(screen(), "Keys", "Bass"):find("Fold 1", 1, true) ~= nil, true, "zw: back, closed as it was")
  keys("zd")
  eq(#paw.folds.list(), 0, "zd deletes it")
  eq(rows_of(screen(), "Keys", "Bass"), rows_of(before, "Keys", "Bass"), "the clips are drawn as before")
end)
