-- The tabs and windows of a seat (paw/layout.lua) as a graphical frontend
-- shows them: panes docked in its main area, laid out in pixels by the
-- rules the terminal lays them out by in cells.
--
-- A frontend says how big its main area is (`area`), and is told with each
-- state (`state`) where every window of the current tab goes, which has the
-- keyboard, the borders between them and the tabs. It draws the views it
-- has its own drawing for (`native`: none now) in their panes, and is sent
-- every other as a scene (paw/scene.lua): a view that paints as a picture
-- at the pane's size, any other cell by cell as the terminal draws it,
-- with the roles it marks (paw/roles.lua) as widgets where it knows them.
-- Pointer events in a pane come to `pointer`; a press anywhere in one gives
-- it the keyboard (`focus`). Keys need nothing: they go to the key mappings
-- with the focused window, as from the terminal.
local api = paw.api
local L = require("paw.layout")

local M = {
  -- Views a frontend draws in its own way.
  native = {},
  -- Views that stay in the layout when they show in a window of their own
  -- too, as a second view of them: the arrange view, the device panel, and
  -- those a frontend draws itself.
  stays = { arrange = true, devices = true },
  -- The least room, in pixels, a view needs in a frontend. An extension
  -- adds its views' (`paw.panes.least.session = { h = 150 }`).
  least = {
    arrange = { w = 320, h = 120 }, devices = { w = 260 }, pianoroll = { h = 200 },
    mixer = { h = 280 },
  },
  -- The height of the row of tabs along the top, when there is more than one.
  tabline = 28,
}

-- Each seat has its own area and windows: its size in pixels, and the last
-- arrangement (for the borders dragged).
local area, last = { w = 0, h = 0 }, nil
paw.seats.keep("panes",
  function() return area, last end,
  function(a, l) area, last = a, l end,
  function() return { w = 0, h = 0 }, nil end)

--- A copy of a tree with its sizes in pixels: a size along a row is in
--- columns, along a column in rows. `map` takes each copy back to its node.
local function in_pixels(node, across, map)
  local cell = paw.canvas.cell
  local unit = across == "h" and cell.w or cell.h
  local copy = { dir = node.dir, view = node.view, id = node.id, hidden = node.hidden, weight = node.weight }
  if node.size then copy.size = math.floor(node.size * unit + 0.5) end
  if node.min then copy.min = math.floor(node.min * unit + 0.5) end
  local least = node.view and M.least[node.view]
  local need = least and (across == "h" and least.w or least.h)
  if need then
    copy.min = math.max(copy.min or 0, need)
    if copy.size then copy.size = math.max(copy.size, need) end
  end
  map[copy] = node
  for i, child in ipairs(node) do copy[i] = in_pixels(child, node.dir == "h" and "h" or "v", map) end
  return copy
end

--- How a pane is drawn: by the frontend itself, painted, or in cells.
local function kind_of(name)
  local view = paw.ui.views[name]
  if M.native[name] then return "native" end
  return view and view.paint and "paint" or "cells"
end

--- What a pane is called: a painted view's title as it was opened, else
--- its buffer's.
local function title_of(win)
  local named = paw.canvas.titles[win.view]
  if named then return named end
  local buf = L.buf_of(win)
  return buf and L.title(buf) or win.view
end

--- The size of the main area in pixels, from the frontend: at the start
--- and each time that it changes. The first time that the window of a seat
--- gives it, paw shows the device panel when the tab has its place, closed,
--- as the default start layout has (`paw.layout.default_tree`): a window
--- shows the devices of the selected track next to the timeline unless the
--- user closes them. A start layout of the configuration's own is shown as
--- it is.
function M.area(width, height)
  local started = area.started
  area = { w = math.max(0, math.floor(width)), h = math.max(0, math.floor(height)), started = started or width > 0 }
  local place = not started and area.w > 0 and L.find(paw.ui.layout, "devices")
  if place and place.hidden and paw.ui.start_layout == nil then paw.ui.show("devices") end
  api.ui_redraw()
end

--- The main area in cells, with the status line and the command line
--- under it as on a terminal: what the seat's screen is. Nil until the
--- frontend has said.
function M.cells()
  if area.w <= 0 or area.h <= 0 then return nil end
  local cell = paw.canvas.cell
  local bars = 0
  for _, node in ipairs(paw.ui.bars) do bars = bars + node.size end
  return { w = math.floor(area.w / cell.w), h = math.floor(area.h / cell.h) + bars }
end

--- The positions of all items in the main area, for the state of a
--- frontend. `panes` is a list of `{ win, view, kind ("native", "paint",
--- "cells"), title, x, y, w, h, focused, titled }`. `borders` is a list of
--- `{ dir, x, y, length }`. For `dir`, "h" is a rule between panes side by
--- side, and "v" is a rule between panes one above the other. `tabs` is a list of
--- `{ title }`, and `tab` is the current tab. `top` is where the panes
--- start, below the row of tabs. Nil until the frontend gives the size of
--- its area.
function M.state()
  if area.w <= 0 or area.h <= 0 then return nil end
  local u = paw.ui
  -- The row of tabs shows as the terminal's tab line does.
  local top = (#u.tabs > 1 or paw.statusline.tabline_always()) and M.tabline or 0
  local map = {}
  local root = in_pixels(u.layout, "v", map)
  local rects = u.place(root, 0, top, area.w, math.max(0, area.h - top))
  last = { rects = rects, map = map }
  local current = L.current()
  local out = { panes = {}, borders = {}, tabs = {}, tab = u.tab, top = top }
  for _, r in ipairs(rects) do
    local win = r.win and L.find_id(u.layout, r.win)
    if win then
      out.panes[#out.panes + 1] = {
        win = win.id, view = win.view, kind = kind_of(win.view), title = title_of(win),
        -- A view whose title row has its own buttons (the piano roll's
        -- tools, its window and close) is shown with it, under no title of
        -- the frontend's.
        titled = paw.ui.views[win.view] and paw.ui.views[win.view].titled or nil,
        x = r.x, y = r.y, w = r.w, h = r.h,
        focused = win == current and u.focused == win.view and not paw.canvas.open_views[win.view],
      }
    end
  end
  for _, b in ipairs(rects.borders) do
    out.borders[#out.borders + 1] = { dir = b.dir, x = b.x, y = b.y, length = b.dir == "h" and b.h or b.w }
  end
  for _, t in ipairs(u.tabs) do out.tabs[#out.tabs + 1] = { title = L.tab_title(t) } end
  return out
end

local function window(id)
  local win = L.find_id(paw.ui.layout, id)
  if win and not win.hidden then return win end
end

--- Give a pane's window the keyboard, as a click in it does.
function M.focus(id)
  local win = window(id)
  if not win or paw.ui.float then return end
  local view = paw.ui.views[win.view]
  if not view or view.focusable == false then return end
  if L.current() ~= win or paw.ui.focused ~= win.view then
    if paw.keymap.mode == "x" then paw.keymap.set_mode("n") end
    L.enter(win)
  end
end

local point

--- A pointer event in a pane, in pixels from its corner (as
--- `paw.canvas.pointer` takes them). A press gives it the keyboard first.
--- For a pane drawn in cells, `drawn` tells how: its `cell`, and its size
--- in cells, `cols` and `rows`. It keeps the button held in a drag.
function M.pointer(id, event, drawn)
  local win = window(id)
  if not win then return end
  if event.kind == "down" then M.focus(id) end
  local view = paw.ui.views[win.view]
  if not view then return end
  -- With the state of this window, then of the one with the keyboard.
  L.bind(win)
  local ok, err = pcall(point, view, id, event, drawn)
  L.settle()
  if not ok then error(err, 0) end
end

-- The event as the view takes it.
function point(view, id, event, drawn)
  if event.kind == "drop" then
    -- A clip dragged from another window let go over this one: the view
    -- takes it in the cell under the pointer, if it takes clips.
    drawn = drawn or {}
    local cell = drawn.cell or paw.canvas.cell
    if view.on_drop then
      view:on_drop({ clip = event.clip, x = math.floor((event.x or 0) / cell.w), y = math.floor((event.y or 0) / cell.h),
        win = id, w = drawn.cols, h = drawn.rows, mods = (event.ctrl and "C" or "") .. (event.shift and "S" or "") })
    end
  elseif view.paint then
    paw.canvas.view_pointer(view, event)
  else
    drawn = drawn or {}
    local e = paw.canvas.cell_event(drawn, event, true)
    if e and view.on_mouse then
      e.win, e.w, e.h = id, drawn.cols, drawn.rows
      paw.limit.named("the mouse", paw.mouse.to_view, view, e)
    end
  end
  api.ui_redraw()
end

--- A border of the last arrangement (by its place in `state().borders`)
--- dragged to `x, y`: as a border dragged in the terminal, the side that
--- has a size keeps one, in whole cells.
function M.border(index, x, y)
  local b = last and last.rects.borders[index]
  if not b then return end
  L.drag_border(b, last.rects, x, y, { unit = paw.canvas.cell, map = last.map })
end

--- Close a pane's window, as `:close` in it would.
function M.close(id)
  local win = window(id)
  if win and not L.close(win) then paw.notify("the last window does not close", "warn") end
end

--- A click on tab `i` goes to it.
function M.tab(i)
  if not paw.ui.float then L.tab_go(i) end
end

--- Close tab `i`, as `:tabclose` does (its close button, a middle click).
function M.tab_close(i)
  if paw.ui.float then return end
  if not L.tab_close(i) then paw.notify("the last tab does not close", "warn") end
end

--- A new tab on the start page, after the current one, as `:tabnew` makes.
function M.tab_new()
  if not paw.ui.float then L.tab_new() end
end

--- Move tab `from` to place `to` among the tabs, as `:tabmove` does (a
--- tab dragged along the row).
function M.tab_move(from, to)
  if not paw.ui.float then L.tab_move(to, from) end
end

return M
