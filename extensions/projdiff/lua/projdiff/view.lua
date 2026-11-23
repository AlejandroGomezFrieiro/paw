-- The difference between two versions of a project as text with folds, in a
-- floating window, after fugitive's diff: a line for each change, a heading
-- over the changes inside a track, a clip or a device that folds them away.
local projdiff = require("projdiff")
local diff = projdiff.diff
local api = paw.api

local view = {
  title = "Project diff",
  modal = true,
  tree = { children = {} },
  title_text = "",
  folded = {}, -- node -> true when closed, false when open, nil for the default
  sel = 1,
  scroll = 0,
  pending = "",
  rows = {},
}

local STYLES = { ["+"] = "Info", ["-"] = "Warn", ["~"] = "Normal", [" "] = "Dim" }

local function is_open(n)
  local state = view.folded[n]
  if state ~= nil then return not state end
  return n.open
end

--- Close what is deeper than the headings of tracks and clips, unless the
--- whole diff is short enough to read at once.
local function default_folds(root)
  local total = 0
  local function size(n)
    total = total + 1
    for _, c in ipairs(n.children) do
      size(c)
    end
  end
  for _, n in ipairs(root.children) do
    size(n)
  end
  local function mark(n, depth)
    n.open = total <= 40 or depth < 2
    for _, c in ipairs(n.children) do
      mark(c, depth + 1)
    end
  end
  for _, n in ipairs(root.children) do
    mark(n, 0)
  end
end

function view:refresh(keep)
  self.rows = diff.flatten(self.tree, is_open)
  if keep then
    for i, row in ipairs(self.rows) do
      if row.node == keep then self.sel = i end
    end
  end
  self.sel = paw.util.clamp(self.sel, 1, math.max(1, #self.rows))
end

local function selected() return view.rows[view.sel] end

function view:render(buf)
  local height = buf.height - 2
  if self.sel <= self.scroll then self.scroll = self.sel - 1 end
  if self.sel > self.scroll + height then self.scroll = self.sel - height end
  buf:text(1, 0, paw.util.fit(self.title_text, buf.width - 2), "HelpSection")
  if #self.rows == 0 then buf:text(1, 2, "no difference", "Dim") end
  for r = 0, height - 1 do
    local row = self.rows[r + 1 + self.scroll]
    if row then
      local n = row.node
      local at = r + 1 + self.scroll == self.sel
      if at then buf:fill(0, r + 1, buf.width, 1, " ", "Selected") end
      local mark = #n.children > 0 and (is_open(n) and "▾ " or "▸ ") or "  "
      local x = 1 + row.depth * 2
      buf:text(x, r + 1, mark, at and "Selected" or "Dim")
      local style = at and "Selected" or (n.change and STYLES[n.sign] or (#n.children > 0 and "Title" or "Dim"))
      local text = n.sign .. " " .. n.text
      if #n.children > 0 and not is_open(n) then text = text .. "  (" .. #n.children .. ")" end
      buf:text(x + 2, r + 1, paw.util.fit(text, math.max(1, buf.width - x - 3)), style)
    end
  end
  buf:text(1, buf.height - 1, "j/k move  Enter go  za fold  zR zM all  ]c [c change  Q quickfix  q", "Dim")
end

local function toggle(n, to)
  if #n.children == 0 then return end
  if to == nil then to = is_open(n) end
  view.folded[n] = to
end

local function set_all(closed)
  local function walk(n)
    if #n.children > 0 then view.folded[n] = closed end
    for _, c in ipairs(n.children) do
      walk(c)
    end
  end
  for _, n in ipairs(view.tree.children) do
    walk(n)
  end
end

--- Move to the next (or previous) line that is a change itself.
local function step(dir)
  local i = view.sel + dir
  while view.rows[i] do
    if view.rows[i].node.change then
      view.sel = i
      return
    end
    i = i + dir
  end
end

--- The block that places subproject `id`, and the subproject that the
--- block is in (nil for the song). A block of the song comes first, as
--- in the diff.
local function placed_by(id)
  local first
  for _, block in ipairs(paw.nest.blocks(id)) do
    local holder = api.track_get(block.row, "nest")
    if holder == nil then return block, nil end
    first = first or { block = block, holder = holder }
  end
  if first then return first.block, first.holder end
end

--- The scopes to enter one after the other, from the song in, to show
--- subproject `id` of the open project. Nil when it has no such subproject.
local function way_into(id)
  local way, seen = {}, {}
  while id and not seen[id] do
    if not paw.nest.get(id) then return nil end
    seen[id] = true
    local block, holder = placed_by(id)
    table.insert(way, 1, { kind = "nest", id = id, clip = block and block.clip.id })
    id = holder
  end
  return way
end

--- Whether the window in front shows the scopes of `way` and no more.
local function shows(way)
  local path = paw.scope.path()
  if #path ~= #way then return false end
  for i, level in ipairs(path) do
    if level.kind ~= "nest" or level.id ~= way[i].id then return false end
  end
  return true
end

--- Put the window in front in the scope of subproject `id`, from the
--- song, and say where it is. Returns false, with a message, when it cannot.
local function enter_nest(id)
  local way = way_into(id)
  if not way then
    paw.notify("the subproject of this change is not in the project now", "warn")
    return false
  end
  if shows(way) then return true end
  paw.scope.widen(true)
  for _, scope in ipairs(way) do
    local ok, err = pcall(paw.scope.enter, scope)
    if not ok then
      paw.notify(tostring(err), "warn")
      return false
    end
  end
  paw.notify(paw.scope.breadcrumb() .. " · `zw` goes back")
  return true
end

--- Close the window and put the cursor where the change is. A change
--- inside a subproject goes inside that subproject first. A change of the
--- song leaves the window in its scope.
local function go()
  local row = selected()
  if not row or not row.node.address then return end
  local qf = paw.qf
  paw.ui.close()
  if row.node.nest and not enter_nest(row.node.nest) then return end
  qf.go({ location = { uri = row.node.address } })
end

local function to_quickfix()
  local n = projdiff.to_quickfix(view.tree, view.title_text)
  paw.notify(n .. " changes are in the quickfix list (`:copen`, `]q`)")
end

local keys = {
  ["j"] = function() view.sel = view.sel + 1 end,
  ["k"] = function() view.sel = view.sel - 1 end,
  ["<Down>"] = function() view.sel = view.sel + 1 end,
  ["<Up>"] = function() view.sel = view.sel - 1 end,
  ["<C-d>"] = function() view.sel = view.sel + 10 end,
  ["<C-u>"] = function() view.sel = view.sel - 10 end,
  ["G"] = function() view.sel = #view.rows end,
  ["<CR>"] = go,
  ["<Tab>"] = function()
    local r = selected()
    if r then
      toggle(r.node)
      view:refresh(r.node)
    end
  end,
  ["Q"] = to_quickfix,
  ["q"] = function() paw.ui.close() end,
  ["<Esc>"] = function() paw.ui.close() end,
}

-- Two keys: `za` `zo` `zc` `zR` `zM`, `]c` `[c`, `gq`.
local pairs_of_keys = {
  za = function()
    local r = selected()
    if r then
      toggle(r.node)
      view:refresh(r.node)
    end
  end,
  zo = function()
    local r = selected()
    if r then
      toggle(r.node, false)
      view:refresh(r.node)
    end
  end,
  zc = function()
    local r = selected()
    if r then
      toggle(r.node, true)
      view:refresh(r.node)
    end
  end,
  zR = function()
    local r = selected()
    set_all(false)
    view:refresh(r and r.node)
  end,
  zM = function()
    local r = selected()
    set_all(true)
    view:refresh(r and r.node)
  end,
  ["]c"] = function() step(1) end,
  ["[c"] = function() step(-1) end,
  gg = function() view.sel = 1 end,
  gq = to_quickfix,
}

function view:on_key(key)
  local combo = self.pending .. key
  if self.pending ~= "" then
    self.pending = ""
    local action = pairs_of_keys[combo]
    if action then action() end
  elseif key == "z" or key == "]" or key == "[" or key == "g" then
    self.pending = key
  elseif keys[key] then
    keys[key]()
  end
  self.sel = paw.util.clamp(self.sel, 1, math.max(1, #self.rows))
  api.ui_redraw()
end

function view:on_mouse(event)
  if event.kind == "scroll_down" then self.sel = self.sel + 3 end
  if event.kind == "scroll_up" then self.sel = self.sel - 3 end
  if event.kind == "down" and self.rows[event.y + self.scroll] then
    self.sel = event.y + self.scroll
    local row = selected()
    if row and #row.node.children > 0 and event.x <= 2 + row.depth * 2 + 2 then
      toggle(row.node)
      self:refresh(row.node)
    end
  end
  self.sel = paw.util.clamp(self.sel, 1, math.max(1, #self.rows))
  api.ui_redraw()
end

paw.ui.view("projdiff", view)

--- Show the changes from one version of a project to another.
function view.open(tree, title)
  view.tree, view.title_text = tree, title
  view.folded, view.sel, view.scroll, view.pending = {}, 1, 0, ""
  default_folds(tree)
  view:refresh()
  paw.ui.open("projdiff", { title = "Project diff", width = 110, height = 32 })
end

return view
