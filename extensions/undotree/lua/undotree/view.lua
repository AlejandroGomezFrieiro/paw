-- The undo tree in a floating window: the tree on the left, newest at the
-- top, and on the right what the selected state changed.
local api = paw.api
local undotree = require("undotree")

local view = {
  title = "Undo tree",
  modal = true,
  sel = 1, -- the selected row
  scroll = 0,
  against = "parent", -- the diff shown: "parent" (what the state's step did) or "current"
  rows = {},
}

local function selected() return view.rows[view.sel] end

--- Read the tree again, keeping the selection on the same state if it is
--- still there, or on `id` when given.
function view:refresh(id)
  local keep = id or (selected() and selected().id)
  self.rows = undotree.rows(undotree.tree())
  self.sel = 1
  for i, row in ipairs(self.rows) do
    if row.id == keep then self.sel = i end
    if not keep and row.state.current then self.sel = i end
  end
end

function view:render(buf)
  if #self.rows == 0 then self:refresh() end
  local tree_w = math.max(20, math.floor(buf.width * 0.55))
  local rows = buf.height - 1
  self.sel = paw.util.clamp(self.sel, 1, #self.rows)
  if self.sel <= self.scroll then self.scroll = self.sel - 1 end
  if self.sel > self.scroll + rows then self.scroll = self.sel - rows end
  for r = 0, rows - 1 do
    local row = self.rows[r + 1 + self.scroll]
    if row then
      local s = row.state
      local style = s.current and "Accent" or (s.name and "Title" or "Normal")
      if r + 1 + self.scroll == self.sel then buf:fill(0, r, tree_w - 1, 1, " ", "Selected") end
      local x = buf:text(1, r, row.graph, "Dim") + 2
      buf:text(
        x,
        r,
        paw.util.fit(undotree.describe(s), math.max(1, tree_w - x - 2)),
        r + 1 + self.scroll == self.sel and "Selected" or style
      )
    end
  end
  for r = 0, rows - 1 do
    buf:text(tree_w, r, paw.draw.g.rule, "Rule")
  end

  -- What the selected state changed.
  local row = selected()
  local right = buf:sub(tree_w + 2, 0, buf.width - tree_w - 3, rows)
  if row then
    local s = row.state
    local from = self.against == "current" and nil or s.parent
    local to = s.id
    local title
    if self.against == "current" then
      local current = api.undo_current()
      from, to = s.id, current
      title = string.format("from #%d to the current state #%d", s.id, current)
    else
      title = s.parent and string.format("what #%d changed (from #%d)", s.id, s.parent) or "the project as opened"
    end
    right:text(0, 0, paw.util.fit(title, right.width), "HelpSection")
    local line = 2
    if from and from ~= to then
      local diff = api.undo_diff(from, to)
      right:text(0, 1, paw.util.fit(undotree.summary(diff), right.width), "Dim")
      for _, item in ipairs(diff.items) do
        if line >= right.height then break end
        local style = item:sub(1, 1) == "+" and "Info" or item:sub(1, 1) == "-" and "Warn" or "Normal"
        right:text(0, line, paw.util.fit(item, right.width), style)
        line = line + 1
      end
    else
      right:text(0, 1, "no change", "Dim")
    end
  end
  buf:text(
    1,
    buf.height - 1,
    "j/k move  Enter go  u ^R undo redo  - + older newer  a mark A  b A/B  n name  c checkpoint  d diff  Space  q",
    "Dim"
  )
end

local function go(id)
  undotree.go(id)
  view:refresh(id)
end

local actions = {
  ["j"] = function() view.sel = view.sel + 1 end,
  ["k"] = function() view.sel = view.sel - 1 end,
  ["<C-d>"] = function() view.sel = view.sel + 10 end,
  ["<C-u>"] = function() view.sel = view.sel - 10 end,
  ["g"] = function() view.sel = 1 end,
  ["G"] = function() view.sel = #view.rows end,
  ["<CR>"] = function()
    local row = selected()
    if row then go(row.id) end
  end,
  ["u"] = function()
    if not paw.undo() then paw.notify("nothing to undo") end
    view:refresh(api.undo_current())
  end,
  ["<C-r>"] = function()
    if not paw.redo() then paw.notify("nothing to redo") end
    view:refresh(api.undo_current())
  end,
  ["-"] = function() view:refresh(undotree.travel(-1, nil, 1) or api.undo_current()) end,
  ["+"] = function() view:refresh(undotree.travel(1, nil, 1) or api.undo_current()) end,
  ["a"] = function()
    local row = selected()
    if row then undotree.mark_a(row.id) end
    view:refresh()
  end,
  ["b"] = function()
    local where, why = undotree.toggle()
    paw.notify(where and ("playing " .. where) or why, where and "info" or "warn")
    view:refresh(api.undo_current())
  end,
  ["n"] = function()
    local row = selected()
    if not row then return end
    paw.ui.input({ prompt = "Name #" .. row.id .. ": ", text = row.state.name or "" }, function(text)
      api.undo_name(text, row.id)
      view:refresh()
    end)
  end,
  ["c"] = function()
    paw.ui.input({ prompt = "Checkpoint name: " }, function(text)
      local ok, err = pcall(undotree.checkpoint, text)
      if not ok then paw.notify(tostring(err), "error") end
      view:refresh()
    end)
  end,
  ["d"] = function() view.against = view.against == "parent" and "current" or "parent" end,
  ["<Space>"] = function()
    if api.transport_get().playing then
      paw.transport.stop()
    else
      paw.transport.play()
    end
  end,
  ["q"] = function() paw.ui.close() end,
  -- Escape closes the tree only while it floats, as a prompt does; in a
  -- window of its own it stays, and `q` closes it.
  ["<Esc>"] = function()
    if paw.ui.float then paw.ui.close() end
  end,
}
actions["<Down>"], actions["<Up>"] = actions.j, actions.k
actions["<BS>"] = actions["-"]

function view:on_key(key)
  local action = actions[key]
  if action then action() end
  api.ui_redraw()
end

function view:on_mouse(event)
  if event.kind == "scroll_down" then self.sel = self.sel + 3 end
  if event.kind == "scroll_up" then self.sel = self.sel - 3 end
  if event.kind == "down" and self.rows[event.y + 1 + self.scroll] then self.sel = event.y + 1 + self.scroll end
  api.ui_redraw()
end

paw.ui.view("undotree", view)

--- Open the tree with the current state selected.
function view.open()
  view.rows = {}
  view:refresh(api.undo_current())
  paw.ui.open("undotree", { title = "Undo tree", width = 120, height = 34 })
end

return view
