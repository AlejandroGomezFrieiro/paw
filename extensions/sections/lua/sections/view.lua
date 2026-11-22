-- The list of sections as a view: where each starts and how long it is,
-- to go to, rename, add and remove. Floating over the terminal's views from
-- `:section.list`, and in a window of its own in the graphical frontend
-- (`:view.window sections`, or the views menu's More).
local api = paw.api
local S = require("sections")
local ui = require("sections.ui")

local view = { title = "Sections", modal = true, sel = 1, scroll = 0, shown = 0 }

local function rows() return S.list() end

--- The section the selection is on, after keeping it in the list.
function view:selected()
  local list = rows()
  self.sel = paw.util.clamp(self.sel, 1, math.max(1, #list))
  return list[self.sel], list
end

function view:render(buf, ctx)
  local _, list = self:selected()
  local current = S.current()
  local height = buf.height - 1
  self.shown = height
  if self.sel <= self.scroll then self.scroll = self.sel - 1 end
  if self.sel > self.scroll + height then self.scroll = self.sel - height end
  if #list == 0 then buf:text(1, 0, "No sections yet. a adds one at the edit cursor.", "Dim") end
  for r = 0, height - 1 do
    local i = r + 1 + self.scroll
    local item = list[i]
    if not item then break end
    local chosen = i == self.sel
    local here = current and current.index == item.index
    if chosen then buf:fill(0, r, buf.width, 1, " ", ctx.focused and "Selected" or "Visual") end
    -- The section under the cursor is marked as on the ruler.
    if here then buf:text(1, r, "▍", "SectionCurrent") end
    local x = 4 + buf:text(3, r, string.format("%2d", i), "Dim")
    buf:text(
      x + 1,
      r,
      paw.util.fit(ui.describe(item), math.max(1, buf.width - x - 2)),
      chosen and "Selected" or (here and "Title" or "Normal")
    )
  end
  buf:text(
    1,
    buf.height - 1,
    paw.util.fit("j/k move  Enter go there  r rename  a add at the cursor  x remove  q close", buf.width - 2),
    "Dim"
  )
end

local function act(fn)
  return function()
    local s = view:selected()
    if s then fn(s) end
  end
end

local actions = {
  j = function() view.sel = view.sel + 1 end,
  k = function() view.sel = view.sel - 1 end,
  g = function() view.sel = 1 end,
  G = function() view.sel = #rows() end,
  -- Floating, the list closes first; in a window of its own it stays open.
  ["<CR>"] = act(function(s)
    if paw.ui.float and paw.ui.float.name == "sections" then paw.ui.close() end
    ui.jump(s)
  end),
  r = act(function(s) paw.cmd("section.rename", { section = s.index }) end),
  a = function() paw.cmd("section.add") end,
  x = act(function(s) paw.cmd("section.remove", { s.index }) end),
  q = function() paw.ui.close() end,
  -- Escape closes the list only while it floats, as a prompt does; in a
  -- window of its own it stays, and `q` closes it.
  ["<Esc>"] = function()
    if paw.ui.float then paw.ui.close() end
  end,
}
actions["<Down>"], actions["<Up>"], actions.l = actions.j, actions.k, actions["<CR>"]

function view:on_key(key)
  local action = actions[key]
  if action then
    action()
    api.ui_redraw()
    return true
  end
end

function view:on_mouse(event)
  if event.kind == "scroll_down" then self.sel = self.sel + 1 end
  if event.kind == "scroll_up" then self.sel = self.sel - 1 end
  if event.kind == "down" then
    local i = event.y + 1 + self.scroll
    if rows()[i] and event.y < self.shown then
      -- A click selects a section; a click on the one selected goes there.
      if i == self.sel then
        actions["<CR>"]()
      else
        self.sel = i
      end
    end
  end
  api.ui_redraw()
end

paw.ui.view("sections", view)

--- On the section under the cursor whenever it is shown.
function view:on_show()
  local current = S.current()
  self.sel, self.scroll = current and current.index or 1, 0
end

--- Show the list, floating.
function view.open()
  view:on_show()
  -- The marks, the number and the description, inside the box.
  local width = 48
  for _, s in ipairs(rows()) do
    width = math.max(width, api.str_width(ui.describe(s)) + 12)
  end
  paw.ui.open("sections", { title = "Sections", width = math.min(width, 80), height = math.min(#rows() + 3, 30) })
end

return view
