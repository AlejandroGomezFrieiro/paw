-- Tests of the tabs and windows as a graphical frontend shows them: panes
-- docked in its main area (paw/panes.tl), laid out in pixels, painted, and
-- given the keyboard; and of views that pop out into windows of their own
-- and give the keyboard back. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api
local L = paw.layout
local P = paw.panes
local function ex(line) return paw.commands.exec(line) end

local W, H = 1200, 700
local initial = L.capture()

local function tidy()
  -- Arranged on the terminal's screen again, as the other tests expect.
  P.area(0, 0)
  L.restore(initial)
  for name in pairs(paw.canvas.open_views) do paw.canvas.close(name) end
  paw.ui.focus("arrange")
end

local function start()
  T.after(tidy)
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do paw.ui.close() end
  tidy()
  P.area(W, H)
end

--- The panes of the state by view, and the pane with the keyboard.
local function panes()
  local by, focused = {}, nil
  for _, p in ipairs(P.state().panes) do
    by[p.view] = p
    if p.focused then focused = p end
  end
  return by, focused
end

--- The text a pane shows, as its scene sends it to a window: run after
--- run, and the text its pictures draw.
local function painted(pane)
  local cell = paw.canvas.cell
  api.scene_forget(0)
  paw.ui.render_scene(pane.view, pane.w / cell.w, pane.h / cell.h, cell, L.find_id(paw.ui.layout, pane.win))
  local patch = api.json_decode(api.scene_end(0, "panes"))
  local out = {}
  for _, node in ipairs(patch.set or {}) do
    if node.t == "run" then out[#out + 1] = node.text end
    for _, op in ipairs(node.ops or (node.blob and api.scene_blob(0, node.blob)) or {}) do
      if op[1] == "m" or op[1] == "t" then out[#out + 1] = op[1] == "m" and op[6] or op[4] end
    end
  end
  api.scene_forget(0)
  return table.concat(out, " ")
end

test("panes: the window's area is laid out as the terminal lays out the tab, the device panel beside the arrange view", function()
  start()
  paw.ui.show("devices")
  local by, focused = panes()
  eq(by.arrange ~= nil and by.devices ~= nil, true, "the arrange view and the device panel")
  eq(by.arrange.kind .. " " .. by.devices.kind, "cells cells", "both the kernel's scenes")
  eq(by.arrange.titled, true, "the arrange view's ruler its first row, under no title of the window's")
  eq(by.devices.x + by.devices.w, W, "the panel along the right edge")
  eq(by.arrange.x + by.arrange.w, by.devices.x, "the arrange view beside it")
  eq(by.arrange.h, H, "the whole height")
  eq(focused and focused.view, "arrange", "the arrange view has the keyboard")
  eq(#P.state().borders, 1, "one border between them")
  eq(P.state().tabs[2], nil, "one tab")
end)

test("panes: :vs paw://lane/N is a pane drawn in cells beside the arrange view, and has the keyboard", function()
  start()
  local t = paw.add_track({ name = "Pad" })
  local lane = t:automate("volume")
  lane:set_points({ { 0, -12 }, { 4, 0 } })
  ex("vs " .. paw.address.lane(lane.id))
  local by, focused = panes()
  eq(by.curve and by.curve.kind, "cells", "the curve is drawn in cells")
  eq(focused and focused.view, "curve", "and has the keyboard")
  eq(by.curve.x, by.arrange.x + by.arrange.w, "beside the arrange view")
  eq(painted(by.curve):find("Volume", 1, true) ~= nil, true, "it shows the lane: " .. painted(by.curve))
  paw.keymap.feed("<C-w>h")
  local _, now = panes()
  eq(now.view, "arrange", "Ctrl-w h goes to the arrange view")
  ex("wincmd l")
  ex("q")
  by = panes()
  eq(by.curve, nil, ":q closes it")
end)

test("panes: Enter on a lane row opens its curve in a pane", function()
  start()
  local t = paw.add_track({ name = "Pad" })
  local lane = t:automate("volume")
  paw.lanes.open(t)
  paw.cursor.set_track(t.id, lane.id)
  paw.keymap.feed("<CR>")
  local by, focused = panes()
  eq(focused and focused.view, "curve", "the curve pane has the keyboard")
  eq(by.curve.w > 100 and by.curve.h > 100, true, "with room to draw in")
end)

test("panes: :copen docks the quickfix list along the bottom, the whole width", function()
  start()
  paw.qf.set({ { address = paw.address.project(), text = "too loud", level = "error" } }, { title = "Test" })
  ex("copen")
  local by, focused = panes()
  eq(focused and focused.view, "qflist", "the list has the keyboard")
  eq(by.qflist.x .. " " .. by.qflist.w, "0 " .. W, "the whole width")
  eq(by.qflist.y + by.qflist.h, H, "along the bottom")
  eq(painted(by.qflist):find("too loud", 1, true) ~= nil, true, "showing its entries")
  ex("cclose")
  eq(panes().qflist, nil, ":cclose closes it")
end)

test("panes: a press gives a pane the keyboard, and a border dragged gives it a size", function()
  start()
  ex("sp quickfix")
  local by = panes()
  P.pointer(by.arrange.win, { kind = "down", x = 10, y = 10, button = "left" })
  local _, focused = panes()
  eq(focused.view, "arrange", "a press in the arrange view's pane")
  P.focus(by.qflist.win)
  _, focused = panes()
  eq(focused.view, "qflist", "and in the list's")
  local index
  for i, b in ipairs(P.state().borders) do
    if b.dir == "v" then index = i end
  end
  P.border(index, 100, H - 10 * paw.canvas.cell.h)
  by = panes()
  eq(math.abs(by.qflist.h - 10 * paw.canvas.cell.h) <= paw.canvas.cell.h, true, "ten rows high: " .. by.qflist.h)
end)

test("panes: tabs are listed with the row of them along the top, and a click on one goes there", function()
  start()
  ex("tabnew mixer")
  local state = P.state()
  eq(#state.tabs, 2, "two tabs")
  eq(state.tab, 2, "the new one")
  eq(state.top, P.tabline, "the panes start under the row of tabs")
  eq(state.panes[1].view .. " " .. state.panes[1].y, "mixer " .. P.tabline, "the mixer fills the tab")
  P.tab(1)
  eq(P.state().tab, 1, "a click goes to tab 1")
  paw.keymap.feed("gt")
  eq(P.state().tab, 2, "gt to the next")
  ex("tabclose")
end)

test("panes: a view that paints is docked where it docks, and popped out it gives the keyboard back when closed", function()
  start()
  local seen = {}
  paw.ui.view("panes_probe", {
    title = "Probe",
    render = function(_, buf) buf:text(0, 0, "probe") end,
    paint = function(_, g, ctx)
      seen.size = ctx.width .. "x" .. ctx.height
      g:text(4, 4, "painted probe")
    end,
    pointer = function(_, e) seen.pointer = e.kind end,
  })
  paw.ui.dock("panes_probe", { side = "bottom", hidden = true })
  paw.canvas.open("panes_probe", { title = "The probe", width = 600, height = 300 })
  eq(paw.canvas.open_views.panes_probe, nil, "no window of its own")
  local by, focused = panes()
  eq(focused and focused.view, "panes_probe", "docked, with the keyboard")
  eq(by.panes_probe.kind .. " " .. by.panes_probe.title, "paint The probe", "painted, under the title it was opened with")
  eq(painted(by.panes_probe), "painted probe", "painted at the pane's size")
  eq(seen.size, by.panes_probe.w .. "x" .. by.panes_probe.h, "the pane's size")
  P.pointer(by.panes_probe.win, { kind = "down", x = 3, y = 3, button = "left" })
  eq(seen.pointer, "down", "the pointer reaches it")
  -- Popped out: the pane goes, and :q in its window brings the keyboard back.
  paw.ui.focus("arrange")
  paw.canvas.open("panes_probe", { window = true })
  eq(paw.canvas.open_views.panes_probe ~= nil, true, "a window of its own on request")
  eq(panes().panes_probe, nil, "and no pane")
  local runs = {}
  for _, op in ipairs(paw.canvas.paint("panes_probe", 600, 300, { bars = true }).ops) do
    if op[1] == "m" then runs[#runs + 1] = op[6] end
  end
  eq(table.concat(runs, " "):find("NOR", 1, true) ~= nil, true, "the status line under it, with the mode: " .. table.concat(runs, " "))
  eq(seen.size, "600x" .. (300 - 2 * paw.canvas.cell.h), "over the status line and the command line")
  paw.canvas.key("panes_probe", "<Esc>")
  eq(paw.canvas.open_views.panes_probe ~= nil, true, "Esc stays in the view")
  paw.canvas.key("panes_probe", ":q<CR>")
  eq(paw.canvas.open_views.panes_probe, nil, ":q closes the window")
  local _, now = panes()
  eq(now.view, "arrange", "the keyboard is back where it was")
  paw.ui.hide("panes_probe")
  paw.ui.views.panes_probe = nil
end)

test("panes: keys typed in the main window while a view is popped out go to the window before it", function()
  start()
  ex("sp quickfix")
  local before = L.current()
  ex("view.window qflist")
  eq(paw.ui.focused, "qflist", "the window of its own has the keyboard")
  paw.frontend.act.keys("<Esc>")
  eq(L.current() == before and paw.ui.focused == before.view, false, "the list's pane went with it")
  paw.canvas.close("qflist")
  eq(paw.ui.focused ~= "qflist", true, "closing the window gives the keyboard back")
end)

test("panes: :view.open docks a view where it docks, else in a window split from this one", function()
  start()
  ex("view.open mixer")
  local by, focused = panes()
  eq(focused.view .. " " .. tostring(by.mixer ~= nil), "mixer true", "the mixer in its place")
  paw.ui.focus("arrange")
  ex("view.open qflist")
  by, focused = panes()
  eq(focused.view, "qflist", "the list split from the arrange view")
  eq(by.qflist.y > by.arrange.y, true, "below it")
end)

test("panes: every kind of buffer paints in a pane without failing", function()
  start()
  local t = paw.add_track({ name = "Pad" })
  local lane = t:automate("volume")
  local clip = t:add_clip({ start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 1 } } })
  paw.cursor.set_track(t)
  local names = {
    paw.address.lane(lane.id), "paw://tempo", "quickfix", "paw://tracks", "paw://sends", "paw://markers",
    "paw://track/" .. t.id .. "/devices",
  }
  -- The views of the runtime and of the extensions loaded, as far as these
  -- tests have loaded them.
  for _, name in ipairs({ "empty", "eventlist", "notation", "drums", "utau", "utau_lyrics", "vinput", "doctor",
    "undotree", "undotree_paint", "mixdiag", "mixdiag_paint", "sections", "tutor", "tracklist" }) do
    if paw.ui.views[name] then names[#names + 1] = name end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    L.restore(initial)
    paw.ui.focus("arrange")
    if name == "eventlist" then paw.ui.views.pianoroll:edit(clip) end
    local view, buf = L.resolve(name)
    local made = view and L.split({ view = view, buf = buf and not buf.single and buf.id or nil })
    if made then
      for _, pane in ipairs(P.state().panes) do
        if pane.win == made.id then
          local text = painted(pane)
          eq(text:find("traceback", 1, true), nil, name .. " paints: " .. text:sub(1, 300))
        end
      end
      -- Closed, so that an empty window's buffer is forgotten with it.
      L.close(made)
    end
  end
end)

test("panes: the window is told the mixer's cursor row, which the keys move", function()
  start()
  local t = paw.add_track({ name = "Pad" })
  paw.cursor.set_track(t)
  paw.ui.focus("mixer")
  local row = paw.frontend.state(-1).modal.mixer_row
  eq(row and row.track, t.id, "the strip under the cursor")
  local function key(r) return r.kind .. r.index .. r.field end
  local before = key(row)
  paw.keymap.feed("j")
  local after = key(paw.frontend.state(-1).modal.mixer_row)
  eq(after ~= before, true, "j moves it down the strip: " .. before .. " to " .. after)
  paw.ui.focus("arrange")
  eq(paw.frontend.state(-1).modal.mixer_row, nil, "and nothing while the mixer has not the keyboard")
end)

test("panes: the piano roll with no clip open is drawn in cells, as the terminal draws it", function()
  start()
  paw.ui.views.pianoroll.clip_id = nil
  paw.ui.focus("pianoroll")
  local by, focused = panes()
  eq(by.pianoroll and by.pianoroll.kind, "cells", "the kernel draws it")
  eq(focused and focused.view, "pianoroll", "with the keyboard")
  eq(painted(by.pianoroll) ~= "", true, "and something is drawn")
end)
