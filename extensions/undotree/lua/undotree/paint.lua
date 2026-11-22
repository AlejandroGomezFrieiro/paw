-- The undo tree in a window of a graphical frontend, painted: a node for each
-- state with the branches drawn between them, the current state lit, a click
-- on a node going there, and what a step was when the pointer rests on it.
-- It works on the terminal view's rows and selection (`undotree.view`), so
-- every key of that view works here too.
local api = paw.api
local undotree = require("undotree")
local term = require("undotree.view")
local canvas = require("paw.canvas")
local c = canvas.palette

local NAME = "undotree_paint"
local HEAD, ROW, GAP, LEFT, FOOT = 34, 24, 18, 22, 24

local paint = {
  title = "Undo tree",
  modal = true,
  window = false,      -- the terminal's view is the one offered; it names this as `painted`
  scroll = 0,          -- rows scrolled off the top
  hover = nil,         -- the row under the pointer, and where the pointer is
  seen = nil,          -- the selected state the scroll last kept in view
}
-- Each window looking at it points and scrolls on its own.
paw.seats.fields("undotree.paint", paint, { "scroll", "hover", "seen" }, { scroll = 0 })

--- The ids from the current state back to the first: the branch that
--- leads here.
local function trunk(tree)
  local on, id = {}, nil
  for _, s in ipairs(tree.states) do
    if s.current then id = s.id end
  end
  while id do
    on[id] = true
    id = tree.by_id[id].parent
  end
  return on
end

--- Where a row's node is, in the tree's own coordinates (the first row at 0).
local function node_at(row, index)
  return LEFT + (row.col - 1) * GAP, (index - 1) * ROW + ROW / 2
end

local function colour_of(s, on_trunk)
  if s.current then return c.select end
  if s.name then return c.play end
  return on_trunk and c.text_2 or c.text_3
end

--- The tree under `g`, scrolled; records the rows for the pointer.
local function draw_tree(self, g, rows, tree, width, height)
  local on = trunk(tree)
  local index_of = {}
  for i, row in ipairs(rows) do index_of[row.id] = i end
  local shown = math.floor(height / ROW)
  if term.sel ~= self.seen then
    self.seen = term.sel
    if term.sel <= self.scroll then self.scroll = term.sel - 1 end
    if term.sel > self.scroll + shown then self.scroll = term.sel - shown end
  end
  self.scroll = paw.util.clamp(self.scroll, 0, math.max(0, #rows - shown))
  local view = g:sub(0, 0, width, height)
  local tree_g = view:sub(0, -self.scroll * ROW, width, #rows * ROW)
  local graph_w = LEFT
  for _, row in ipairs(rows) do graph_w = math.max(graph_w, LEFT + (row.lanes - 1) * GAP) end
  local text_x = graph_w + 20
  self.rows, self.shown, self.height = rows, shown, height

  for i, row in ipairs(rows) do
    local y = (i - 1) * ROW
    if i == term.sel then
      tree_g:rect(0, y, width, ROW, { fill = c.panel_sel })
    elseif self.hover and self.hover.row == i then
      tree_g:rect(0, y, width, ROW, { fill = c.panel })
    end
  end
  -- A branch is the child's lane down to its parent's row, then across.
  for i, row in ipairs(rows) do
    local s = row.state
    local j = s.parent and index_of[s.parent]
    if j then
      local x, y = node_at(row, i)
      local px, py = node_at(rows[j], j)
      local lit = on[row.id] and on[s.parent]
      tree_g:poly(px == x and { x, y, px, py } or { x, y, x, py, px, py },
        { color = lit and c.select or c.line_bar, width = lit and 2 or 1.5 })
    end
  end
  for i, row in ipairs(rows) do
    local s = row.state
    local x, y = node_at(row, i)
    local r = s.current and 7 or 5
    tree_g:rect(x - r, y - r, 2 * r, 2 * r, {
      fill = colour_of(s, on[row.id]), radius = r,
      stroke = s.current and c.text or (s.id == undotree.a or s.id == undotree.b) and c.select or "",
      width = 2,
    })
    local style = s.current and c.select or s.name and c.play or on[row.id] and c.text or c.text_2
    tree_g:text(text_x, y - 7, string.format("#%d", s.id), { color = c.text_3, size = 11 })
    tree_g:text(text_x + 34, y - 7, undotree.when(s.time), { color = c.text_3, size = 11 })
    local tags = (s.name and ('"' .. s.name .. '"  ') or "")
      .. (s.id == undotree.a and "[A] " or "") .. (s.id == undotree.b and "[B] " or "")
      .. (s.saved and "(saved) " or "")
    tree_g:text(text_x + 120, y - 7, tags .. undotree.what(s), { color = style, size = 12, bold = s.current, width = width - text_x - 126 })
  end
end

--- What the selected state changed, in the panel at the right.
local function draw_diff(self, g, tree)
  local row = term.rows[term.sel]
  if not row then return end
  local s = row.state
  local from, to, title = s.parent, s.id
  if term.against == "current" then
    from, to = s.id, api.undo_current()
    title = string.format("from #%d to the current state #%d", from, to)
  else
    title = s.parent and string.format("what #%d changed (from #%d)", s.id, s.parent) or "the project as opened"
  end
  g:text(0, 0, title, { color = c.text, size = 13, bold = true, width = g.width })
  if from and from ~= to then
    local key = from .. ">" .. to .. ":" .. #tree.states
    if self.diff_key ~= key then self.diff_key, self.diff = key, api.undo_diff(from, to) end
    g:text(0, 22, undotree.summary(self.diff), { color = c.text_2, width = g.width })
    local y = 46
    for _, item in ipairs(self.diff.items) do
      if y + 16 > g.height then break end
      local mark = item:sub(1, 1)
      g:text(0, y, item, { color = mark == "+" and c.play_on or mark == "-" and c.warn or c.text, width = g.width })
      y = y + 17
    end
  else
    g:text(0, 22, "no change", { color = c.text_3 })
  end
end

--- A box that says what the state under the pointer was.
local function draw_tip(self, g, width, height)
  local hover = self.hover
  local row = hover and self.rows[hover.row]
  if not row then return end
  local s = row.state
  local lines = {
    { string.format("#%d  %s", s.id, undotree.what(s)), c.text, true },
    { (s.name and ('"' .. s.name .. '"  ') or "") .. undotree.when(s.time) .. "  (" .. undotree.ago(s.time) .. " ago)", c.text_2 },
  }
  if s.parent then
    lines[3] = { "after #" .. s.parent .. (s.current and "  ·  this is where you are" or "  ·  click to go there"), c.text_3 }
  end
  local w = 0
  for _, line in ipairs(lines) do w = math.max(w, api.str_width(line[1]) * 7 + 20) end
  local h = #lines * 18 + 12
  local x = math.min(hover.x + 16, width - w - 6)
  local y = math.min(hover.y + 18, height - h - FOOT - 4)
  g:rect(x, y, w, h, { fill = c.card, stroke = c.card_line, radius = 5 })
  for i, line in ipairs(lines) do
    g:text(x + 10, y + 7 + (i - 1) * 18, line[1], { color = line[2], bold = line[3] })
  end
end

--- The foot of the window: a prompt when one is open, else the keys.
local function draw_foot(g, width, height)
  local y = height - FOOT
  g:rect(0, y, width, FOOT, { fill = c.panel })
  local cell = canvas.cell
  local line = api.ui_view_snapshot("cmdline", math.max(1, math.floor(width / cell.w)), 1)
  if line.cursor then
    for _, run in ipairs(line.rows[1]) do
      g:mono(run.x * cell.w, y + (FOOT - cell.h) / 2, run.text, { color = run.fg, background = run.bg })
    end
    g:rect(line.cursor.x * cell.w, y + (FOOT - cell.h) / 2, 2, cell.h, { fill = c.text })
  else
    g:text(12, y + 6, "click a state to go there   j k move   Enter go   u Ctrl-r undo redo   a mark A   b A/B   n name   c checkpoint   d diff   q close",
      { color = c.text_3, size = 11, width = width - 24 })
  end
end

function paint:paint(g, ctx)
  local width, height = ctx.width, ctx.height
  term:refresh()
  local tree = undotree.tree()
  g:rect(0, 0, width, height, { fill = c.surface })
  g:text(14, 9, "Undo tree", { color = c.text, size = 14, bold = true })
  g:text(110, 11, string.format("%d states", #tree.states), { color = c.text_3, size = 11 })
  g:line(0, HEAD - 0.5, width, HEAD - 0.5, { color = c.divider })
  local body = height - HEAD - FOOT
  local tree_w = math.max(300, math.floor(width * 0.6))
  draw_tree(self, g:sub(0, HEAD, tree_w, body), term.rows, tree, tree_w, body)
  g:line(tree_w + 0.5, HEAD, tree_w + 0.5, height - FOOT, { color = c.divider })
  draw_diff(self, g:sub(tree_w + 14, HEAD + 12, width - tree_w - 24, body - 12), tree)
  draw_foot(g, width, height)
  draw_tip(self, g, width, height)
end

function paint:pointer(e)
  local i = self.rows and e.y >= HEAD and e.y < HEAD + self.height and math.floor((e.y - HEAD) / ROW) + 1 + self.scroll
  if i and not self.rows[i] then i = nil end
  if e.kind == "hover" or e.kind == "move" then
    self.hover = i and { row = i, x = e.x, y = e.y } or nil
  elseif e.kind == "wheel" then
    self.scroll = math.max(0, self.scroll + ((e.dy or 0) > 0 and -3 or 3))
    self.hover = nil
  elseif e.kind == "down" and e.button == "left" and i then
    term.sel = i
    undotree.go(self.rows[i].id)
    term:refresh(self.rows[i].id)
  end
end

local keys = term.on_key
function paint:on_key(key)
  if key == "q" or key == "<Esc>" then return canvas.close(NAME) end
  keys(term, key)
end

paw.ui.view(NAME, paint)
term.painted = NAME

return paint
