-- The default commands and keys: sizes. Loaded by paw/defaults.lua;
-- like it, it uses nothing but the public `paw` module.
local util = paw.util
local command, map = paw.command, paw.keymap.set

--
-- Every size is an option, so a configuration can set it: `track_height`
-- and `header_width` ("auto" fits them to the screen), and for a panel beside
-- the arrange view `<name>_width`, for one above or below it
-- `<name>_height` (0 shares the space): `devices_width`, `mixer_height`,
-- `pianoroll_height`.

paw.option.define("devices_width", 36)
paw.option.define("mixer_height", 12)
paw.option.define("pianoroll_height", 0)

--- A view's place in the layout: its node, and whether it sits in a row
--- beside others (it has a width) or in the column (a height).
local function layout_node(name)
  local function find(node, in_row)
    if node.view == name then return node, in_row end
    for _, child in ipairs(node) do
      local found, row = find(child, node.dir == "h")
      if found then return found, row end
    end
  end
  return find(paw.ui.layout, false)
end

paw.on("option.changed", function(e)
  local name, what = tostring(e.name):match("^(.+)_(%a+)$")
  if what ~= "width" and what ~= "height" then return end
  local node, in_row = layout_node(name)
  if not node or in_row ~= (what == "width") then return end
  local value = tonumber(e.value) or 0
  node.size = value > 0 and math.floor(value) or nil
end)

--- How many columns or rows a view has on screen now.
local function drawn_size(name, what)
  for _, rect in ipairs(paw.ui.arrange()) do
    if rect.name == name then return what == "width" and rect.w or rect.h end
  end
end

--- Change a size option by `by`, starting from what is drawn when it is 0.
local function resize(option, by, view, what, least)
  local now = tonumber(paw.opt[option]) or 0
  if now <= 0 then now = view and drawn_size(view, what) or 0 end
  paw.opt[option] = math.max(least or 1, now + by)
  paw.notify(string.format("%s %d", option, paw.opt[option]))
end

--- Whether the arrange view is the only window: then the size keys size
--- its tracks and headers, as there is no window to share with.
local function arrange_alone()
  local wins = paw.layout.focusable_windows()
  return paw.ui.focused == "arrange" and #wins == 1 and wins[1].view == "arrange"
end

-- The height of tracks, lanes and keys is the vertical zoom
-- (paw/vzoom.tl: `<C-=>`, `<C-->`, `<C-0>`, `z+`, `z-`, `z=`); these
-- keys size windows only.
command("view.height", function(ctx)
  local by = (tonumber(ctx.args[1]) or 1) * (ctx.count or 1)
  local name = paw.ui.focused
  local node, in_row = layout_node(name)
  if name ~= "arrange" and node and not in_row then return resize(name .. "_height", by, name, "height", 3) end
  if paw.layout.resize(nil, "height", by, true) then return end
  paw.notify("no window above or below to share the height with · `Ctrl-=` or `z+` makes the rows taller", "warn")
end, { desc = "A taller window, or a taller panel: `view.height 2`, `view.height -1`" })
command("view.width", function(ctx)
  local by = (tonumber(ctx.args[1]) or 2) * (ctx.count or 1)
  local name = paw.ui.focused
  local node, in_row = layout_node(name)
  if name ~= "arrange" and node and in_row then return resize(name .. "_width", by, name, "width", 12) end
  if not arrange_alone() and paw.layout.resize(nil, "width", by, true) then return end
  local now = tonumber(paw.opt.header_width)
  -- The headers' own width, without the track column at their left.
  local g = paw.ui.views.arrange.geometry
  if not now then now = g and g.hw - g.layout.column.width or 24 end
  paw.opt.header_width = util.clamp(now + by, 8, 60)
  paw.notify("header width " .. paw.opt.header_width)
end, { desc = "A wider side panel, or track header in the arrange view: `view.width 4`, `view.width -2`" })
command("view.equal", function() paw.layout.equalize() end, { desc = "Windows of equal size" })
command("view.maximize", function()
  if paw.layout.maximize() then
    paw.notify(paw.ui.focused .. " fills the screen; `Ctrl-w _` again puts the others back")
  end
end, { desc = "Give the focused window the whole tab, or put the others back" })

map("<C-w>d", "view.dock", { desc = "Put a view in a window of its own back in the main window, as a pane" })
map("<C-^>", function() paw.layout.alternate() end, { desc = "Show what this window showed before, as `:b #` does" })
map("<C-w>+", "view.height 1", { desc = "Taller window" })
map("<C-w>-", "view.height -1", { desc = "Shorter window" })
map("<C-w>=", "view.equal", { desc = "Windows of equal size" })

-- Vertical zoom (paw/vzoom.tl). Most terminals send nothing of their own
-- for Ctrl with = - 0 (paw-tui asks for no keyboard protocol), so `z+`
-- `z-` `z=` do the same everywhere; the graphical window sends both.
local nx = { "n", "x" }
local taller = "Taller rows: tracks (a selection or a count: those tracks), the lane at the cursor, piano roll keys"
local shorter = "Shorter rows: tracks (a selection or a count: those tracks), the lane at the cursor, piano roll keys"
local fit = "Rows as tall as the options say: tracks fit the window again, one row per piano roll key"
for _, k in ipairs({
  { { "<C-=>", "<C-+>" }, "z+", "vzoom 1", taller },
  { { "<C-->" }, "z-", "vzoom -1", shorter },
  { { "<C-0>" }, "z=", "vzoom fit", fit },
}) do
  for _, lhs in ipairs(k[1]) do
    map(lhs, k[3], {
      mode = nx,
      desc = k[4] .. " (the graphical window; most terminals do not send it: `" .. k[2] .. "` works everywhere)",
    })
  end
  map(k[2], k[3], { mode = nx, desc = k[4] })
end
map("<C-w><lt>", "view.width -2", { desc = "Narrower window; with the arrange view alone, track headers" })
map("<C-w>>", "view.width 2", { desc = "Wider window; with the arrange view alone, track headers" })
map("<C-w>_", "view.maximize", { desc = "Give the window the whole tab, or put the others back" })
