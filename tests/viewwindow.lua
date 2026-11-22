-- Tests of views in windows of their own (`paw.canvas.open_view`), drawn
-- cell by cell as the terminal draws them, and of extensions' bands under
-- the window's ruler. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

local function start()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  for name in pairs(paw.canvas.open_views) do
    paw.canvas.close(name)
  end
  paw.ui.focus("arrange")
end

--- A row of runs as the text it shows.
local function row_text(row)
  local parts = {}
  for _, run in ipairs(row) do
    parts[#parts + 1] = run.text
  end
  return (table.concat(parts):gsub("%s+$", ""))
end

--- What a cell window shows, as lines of text from its "m" operations.
local function painted_text(ops, cell)
  local lines = {}
  for _, op in ipairs(ops) do
    if op[1] == "m" then
      local row, col = math.floor(op[3] / cell.h + 0.5) + 1, math.floor(op[2] / cell.w + 0.5)
      lines[row] = lines[row] or {}
      lines[row][#lines[row] + 1] = { col = col, text = op[6] }
    end
  end
  local out = {}
  for row, runs in pairs(lines) do
    table.sort(runs, function(a, b) return a.col < b.col end)
    local line = ""
    for _, run in ipairs(runs) do
      line = line .. string.rep(" ", run.col - api.str_width(line)) .. run.text
    end
    out[row] = line:gsub("%s+$", "")
  end
  return out
end

-- A view of the tests' own: some text in a group, a box, and what it was given.
local seen = { keys = {}, mouse = {} }
paw.ui.hl("ViewWindowTest", { fg = "#123456", bg = "#fedcba", bold = true })
local probe = {
  title = "Probe",
  modal = true,
  render = function(_, buf)
    buf:text(0, 0, "probe ┌──┐", "ViewWindowTest")
    buf:text(0, 1, "plain │  │")
    buf:text(0, 2, "keys " .. table.concat(seen.keys, ","))
  end,
  on_key = function(_, key) seen.keys[#seen.keys + 1] = key end,
  on_mouse = function(_, e) seen.mouse[#seen.mouse + 1] = e end,
}
paw.ui.view("viewwindow_probe", probe)

test("a view drawn by itself has the text it shows in the terminal", function()
  start()
  -- In the terminal, floating: the box's inside is the view.
  paw.ui.open("viewwindow_probe", { title = "Probe", width = 30, height = 6 })
  local screen = api.ui_snapshot(80, 24)
  local rect
  for _, r in ipairs(paw.ui.rects) do
    if r.name == "viewwindow_probe" then rect = r end
  end
  local snap = api.ui_view_snapshot("viewwindow_probe", rect.w, rect.h)
  eq(snap.width .. "x" .. snap.height, rect.w .. "x" .. rect.h, "the size asked for")
  for y = 0, rect.h - 1 do
    local chars = {}
    for ch in screen[rect.y + y + 1]:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      chars[#chars + 1] = ch
    end
    local shown = table.concat(chars, "", rect.x + 1, math.min(#chars, rect.x + rect.w)):gsub("%s+$", "")
    eq(row_text(snap.rows[y + 1]), shown, "row " .. y)
  end
  paw.ui.close()
end)

test("a view's runs have its groups' colours and attributes, whatever the terminal shows", function()
  start()
  local before = paw.opt.termcolors
  paw.opt.termcolors = "256"
  local ok, err = pcall(function()
    local snap = api.ui_view_snapshot("viewwindow_probe", 20, 3)
    local run = snap.rows[1][1]
    eq(run.text, "probe ┌──┐", "the first run is the text in the group")
    eq(run.fg .. " " .. run.bg .. " " .. run.attrs, "#123456 #fedcba 1", "in 24 bits, bold")
    local normal = snap.rows[2][1]
    eq(normal.fg .. " " .. normal.bg, snap.fg .. " " .. snap.bg, "plain text is in the Normal group's colours")
    eq(#snap.rows[1], 2, "one run for the text and one for the rest of the row")
  end)
  paw.opt.termcolors = before
  if not ok then error(err, 0) end
end)

test("a highlight group's number draws as its name does, and follows the group when it changes", function()
  start()
  local id = api.hl_id("ViewWindowNumbered")
  eq(api.hl_id("ViewWindowNumbered"), id, "a name has one number")
  paw.ui.view("viewwindow_numbered", {
    render = function(_, buf)
      api.grid_text(buf.x, buf.y, "by name", "ViewWindowNumbered", buf.x, buf.y, buf.width, buf.height)
      api.grid_text(buf.x, buf.y + 1, "by number", id, buf.x, buf.y, buf.width, buf.height)
    end,
  })
  -- The number was given before the group had a style.
  paw.ui.hl("ViewWindowNumbered", { fg = "#112233" })
  local snap = api.ui_view_snapshot("viewwindow_numbered", 20, 2)
  eq(snap.rows[2][1].fg, "#112233", "the number draws in the group's style")
  eq(snap.rows[1][1].fg, snap.rows[2][1].fg, "as the name does")
  paw.ui.hl("ViewWindowNumbered", { fg = "#445566" })
  snap = api.ui_view_snapshot("viewwindow_numbered", 20, 2)
  eq(snap.rows[2][1].fg, "#445566", "and follows the group when the theme changes it")
end)

test("drawing a view for a window leaves the terminal's screen as it was", function()
  start()
  local screen = api.ui_snapshot(80, 24)
  local redraws = api.ui_redraws()
  paw.canvas.open_view("viewwindow_probe")
  eq(paw.ui.focused, "viewwindow_probe", "the view has the keyboard")
  paw.ui.focus("arrange")
  redraws = api.ui_redraws()
  api.ui_view_snapshot("viewwindow_probe", 40, 10)
  local painted = paw.canvas.paint("viewwindow_probe", 400, 200, { cell = { w = 10, h = 20 } })
  eq(api.ui_redraws(), redraws, "no redraw is asked for by drawing it")
  eq(table.concat(api.ui_snapshot(80, 24), "\n"), table.concat(screen, "\n"), "the terminal's screen is unchanged")
  eq(painted_text(painted.ops, { w = 10, h = 20 })[1], "probe ┌──┐", "the window's first line")
end)

test("a view's window is drawn again only when it has changed", function()
  start()
  seen.keys = {}
  paw.canvas.open_view("viewwindow_probe")
  local opts = { cell = { w = 10, h = 20 } }
  local first = paw.canvas.paint("viewwindow_probe", 400, 200, opts)
  eq(first.same, nil, "the first time it is drawn")
  eq(#first.ops > 2, true, "with something in it")
  eq(paw.canvas.paint("viewwindow_probe", 400, 200, opts).same, true, "then not, with nothing new")
  api.ui_redraw()
  eq(paw.canvas.paint("viewwindow_probe", 400, 200, opts).same, true, "a redraw that changes nothing sends nothing")
  paw.canvas.key("viewwindow_probe", "z")
  local again = paw.canvas.paint("viewwindow_probe", 400, 200, opts)
  eq(again.same, nil, "a key the view shows draws it again")
  eq(painted_text(again.ops, opts.cell)[3], "keys z", "what it shows now")
  eq(paw.canvas.paint("viewwindow_probe", 500, 200, opts).same, nil, "and so does another size")
  eq(
    paw.canvas.paint("viewwindow_probe", 500, 200, { cell = opts.cell, fresh = true }).same,
    nil,
    "and a window that has nothing yet"
  )
end)

test("keys typed in a view's window reach it with it focused", function()
  start()
  seen.keys = {}
  paw.canvas.open_view("viewwindow_probe")
  paw.ui.focus("arrange")
  paw.canvas.key("viewwindow_probe", "Z")
  eq(paw.ui.focused, "viewwindow_probe", "the view has the keyboard again")
  eq(seen.keys[#seen.keys], "Z", "and the key")
  -- Keys from the main window go to the arrange view instead.
  paw.frontend.act.keys("<Esc>")
  eq(paw.ui.focused, "arrange", "the main window's keys are the arrange view's")
end)

test("the pointer in a view's window reaches its on_mouse in cells, as in the terminal", function()
  start()
  seen.mouse = {}
  paw.canvas.open_view("viewwindow_probe")
  paw.ui.focus("arrange")
  paw.canvas.paint("viewwindow_probe", 400, 200, { cell = { w = 10, h = 20 } })
  paw.canvas.pointer("viewwindow_probe", { kind = "down", x = 35, y = 45, button = "right", shift = true })
  paw.canvas.pointer("viewwindow_probe", { kind = "move", x = 55, y = 45, button = "left" })
  paw.canvas.pointer("viewwindow_probe", { kind = "up", x = 55, y = 45, button = "right" })
  paw.canvas.pointer("viewwindow_probe", { kind = "double", x = 55, y = 45 })
  paw.canvas.pointer("viewwindow_probe", { kind = "wheel", x = 5, y = 5, dx = 0, dy = -120 })
  paw.canvas.pointer("viewwindow_probe", { kind = "wheel", x = 5, y = 5, dx = 0, dy = 120 })
  local got = {}
  for _, e in ipairs(seen.mouse) do
    got[#got + 1] = string.format("%s %s %d,%d %s", e.kind, e.button, e.x, e.y, e.mods)
  end
  eq(
    table.concat(got, "; "),
    "down right 3,2 S; drag right 5,2 ; up right 5,2 ; scroll_down  0,0 ; scroll_up  0,0 ",
    "down, drag with the button held, up, and the wheel; the double click comes as a second down and up"
  )
  eq(paw.ui.focused, "viewwindow_probe", "a click gives the view the keyboard")
  seen.mouse = {}
  paw.canvas.pointer("viewwindow_probe", { kind = "down", x = 5, y = 195, button = "left" })
  eq(#seen.mouse, 0, "the line under the view is not the view's")
end)

test("a floating view moves into a window, and closing it closes the window", function()
  start()
  paw.ui.open("viewwindow_probe", { title = "The probe", width = 30, height = 6 })
  paw.cmd("view.window")
  eq(paw.ui.float, nil, "no longer floating")
  local w = paw.canvas.windows()[1]
  eq(w and w.name, "viewwindow_probe", "in a window")
  eq(w.title .. " " .. tostring(w.cells), "The probe true", "with the float's title, drawn in cells")
  paw.ui.close()
  eq(#paw.canvas.windows(), 0, "closing the view closes its window")
  eq(paw.ui.focused, "arrange", "and the keyboard goes back")
end)

test("the views that can be opened in a window are those that take the keyboard", function()
  start()
  local names = {}
  for _, v in ipairs(paw.canvas.openable()) do
    names[v.name] = v.title
  end
  eq(names.viewwindow_probe, "Probe", "a view's own title")
  eq(names.mixer, nil, "not the mixer, which the window has of its own")
  eq(names.help, nil, "nor a page that needs something to show")
  eq(names.status, nil, "nor the status line")
  eq(names.cmdline, nil, "nor the command line")
  local state = paw.frontend.state(-1)
  eq(#state.modal.views > 0, true, "the frontend is told them")
end)

test("a view in a window shows a prompt on its last line, and keys answer it", function()
  start()
  local answer
  local asking = {
    modal = true,
    render = function(_, buf) buf:text(0, 0, "ask") end,
    on_key = function(_, key)
      if key == "n" then paw.ui.input({ prompt = "Name: " }, function(text) answer = text end) end
    end,
  }
  paw.ui.view("viewwindow_asking", asking)
  paw.canvas.open_view("viewwindow_asking")
  local cell = { w = 10, h = 20 }
  paw.canvas.key("viewwindow_asking", "n")
  local lines = painted_text(paw.canvas.paint("viewwindow_asking", 300, 100, { cell = cell, fresh = true }).ops, cell)
  eq((lines[5] or ""):match("^Name:") ~= nil, true, "the prompt is on the last line: " .. tostring(lines[5]))
  for _, key in ipairs({ "a", "b", "<CR>" }) do
    paw.canvas.key("viewwindow_asking", key)
  end
  eq(answer, "ab", "typed in the window")
  paw.canvas.close("viewwindow_asking")
  paw.ui.views.viewwindow_asking = nil
end)

test("g:mono draws a run of cells with a background, cut by whole cells", function()
  start()
  local cell = paw.canvas.cell
  paw.canvas.cell = { w = 10, h = 20 }
  local ops = {}
  local g = paw.canvas.Painter
  local p = setmetatable({ ops = ops, x = 0, y = 0, width = 100, height = 100 }, g):sub(0, 0, 45, 100)
  p:mono(-10, 0, "abcdef", { color = "#ffffff", background = "#000000", bold = true, underline = true })
  paw.canvas.cell = cell
  local op = ops[1]
  eq(op[1] .. " " .. op[2] .. " " .. op[4] .. " " .. op[6], "m 0 40 bcde", "the cells inside, from the second")
  eq(op[7] .. " " .. op[8] .. " " .. op[9], "#ffffff #000000 9", "colours and attributes")
end)

-- Bands ---------------------------------------------------------------------------

test("an extension's band is under the ruler, and a click runs what it stands for", function()
  start()
  local ran
  local bands = paw.frontend.bands
  local at = #bands + 1
  bands[at] = function()
    return {
      { beat = 0, length = 8, name = "Verse", command = "transport.start" },
      { beat = 8, length = 0, name = "here", color = "#ff0000", run = function(e) ran = e.name end },
      { beat = 12, length = 4, name = "nothing to do" },
    }
  end
  bands[at + 1] = function() return {} end
  local ok, err = pcall(function()
    local state = paw.frontend.band_state()
    local mine = {}
    for _, e in ipairs(state.entries) do
      if e.band == at then mine[#mine + 1] = e end
    end
    eq(#mine, 3, "its entries")
    eq(mine[1].row, state.rows - 1, "a row of its own; the empty band after it takes none")
    eq(
      mine[2].color .. " " .. tostring(mine[2].active) .. " " .. tostring(mine[3].active),
      "#ff0000 true false",
      "colour, and whether a click does anything"
    )
    eq(paw.frontend.state(-1).project.bands.rows, state.rows, "the frontend is told them with the project")
    paw.frontend.act.band(at, 2)
    eq(ran, "here", "a click runs its function")
    api.transport_seek(8)
    paw.frontend.act.band(at, 1)
    eq(paw.transport.position, 0, "or its command")
  end)
  bands[at + 1], bands[at] = nil, nil
  if not ok then error(err, 0) end
end)
