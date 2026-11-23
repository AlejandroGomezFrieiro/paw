-- The conflicts that a merge left in the open project, to settle one by
-- one: ours, theirs or what it was before. They are grouped as the diff
-- groups its changes: a conflict inside a subproject is under the
-- subproject's name. Each choice changes the open project as one undo
-- step, and the project holds the conflicts that are left until a save.
local projdiff = require("projdiff")
local merge = projdiff.merge
local data = projdiff.data
local diff = projdiff.diff
local api = paw.api

local view = {
  title = "Merge conflicts",
  modal = true,
  doc = nil, -- the open project as a decoded file, read again after each choice
  rows = {}, -- the lines of the list: `{ depth, heading }` or `{ depth, conflict }`
  order = {}, -- the conflicts in the order of the list
  sel = 1, -- the selected conflict, an index of `order`
  scroll = 0,
  pending = "",
}

--- The subproject that conflict `c` is inside, or nil for the song: the
--- subproject that its path names, or the subproject of the track that
--- its path names.
local function nest_of(doc, c)
  local path = c.path
  if path[1] ~= "project" or type(path[3]) ~= "table" then return nil end
  if path[2] == "nests" then return path[3].id end
  if path[2] ~= "tracks" then return nil end
  local track = merge.at(doc, { path[1], path[2], path[3] })
  if track then return track.nest end
  -- A track that ours removed is only in the other values of the conflict.
  if #path ~= 3 then return nil end
  for _, side in ipairs({ "theirs", "base" }) do
    if type(c[side]) == "table" then return c[side].nest end
  end
end

--- The lines of the list, from the conflicts of `doc`: those of the song
--- first, then each subproject under its heading, a subproject that
--- another places under that one's heading.
local function build(doc)
  local project = doc.project
  local by_nest, song = {}, {}
  for _, c in ipairs(merge.conflicts(doc)) do
    local nest = nest_of(doc, c)
    if nest then
      by_nest[nest] = by_nest[nest] or {}
      table.insert(by_nest[nest], c)
    else
      song[#song + 1] = c
    end
  end
  local parent = diff.nest_parents(project)
  local rows, order = {}, {}
  local function conflict_row(c, depth)
    rows[#rows + 1] = { depth = depth, conflict = c }
    order[#order + 1] = c
  end
  -- Whether a subproject, or one that it places, holds a conflict.
  local function holds(id)
    if by_nest[id] then return true end
    for child, p in pairs(parent) do
      if p == id and holds(child) then return true end
    end
    return false
  end
  local function nest_rows(n, depth)
    if not holds(n.id) then return end
    rows[#rows + 1] = { depth = depth, heading = diff.nest_label(n) }
    for _, c in ipairs(by_nest[n.id] or {}) do
      conflict_row(c, depth + 1)
    end
    for _, child in ipairs(project.nests or {}) do
      if parent[child.id] == n.id then nest_rows(child, depth + 1) end
    end
  end
  for _, c in ipairs(song) do
    conflict_row(c, 0)
  end
  for _, n in ipairs(project.nests or {}) do
    if parent[n.id] == false then nest_rows(n, 0) end
  end
  -- A conflict of a subproject that the project does not have now.
  for _, id in ipairs(data.sorted_keys(by_nest)) do
    if parent[id] == nil then
      for _, c in ipairs(by_nest[id]) do
        conflict_row(c, 0)
      end
    end
  end
  return rows, order
end

--- Read the open project and its conflicts again.
local function refresh()
  view.doc = projdiff.state(nil)
  view.rows, view.order = build(view.doc)
  view.sel = paw.util.clamp(view.sel, 1, math.max(1, #view.order))
end

--- Settle the conflicts of `list` with `side` of each, in the open
--- project, as one undo step.
local function settle(list, side)
  if #list == 0 then return end
  local doc = projdiff.state(nil)
  for _, c in ipairs(list) do
    merge.resolve(doc, c, side)
  end
  local ok, err = pcall(api.project_replace, doc.project)
  if not ok then return paw.notify("cannot settle: " .. tostring(err):match("[^\n]*"), "error") end
  local words = { ours = "ours", theirs = "theirs", base = "the value before" }
  api.undo_label("take " .. words[side])
  api.undo_checkpoint()
  refresh()
  if #view.order == 0 then
    paw.notify("every conflict is settled: `:w` saves the project, then `git add` it to finish the merge")
    paw.ui.close()
  else
    paw.notify(string.format("took %s; %d left", words[side], #view.order))
  end
end

--- The line of the list where the selected conflict is.
local function selected_row()
  local c = view.order[view.sel]
  for i, row in ipairs(view.rows) do
    if row.conflict == c then return i end
  end
  return 1
end

function view:render(buf)
  local rows = buf.height - 8
  local at_row = selected_row()
  if at_row <= self.scroll then self.scroll = at_row - 1 end
  if at_row > self.scroll + rows then self.scroll = at_row - rows end
  local n = #self.order
  local path = api.project_get("path") or "the project"
  local name = path:gsub("/project%.toml$", ""):match("[^/]*$")
  local title = string.format("%s: %d conflict%s", name, n, n == 1 and "" or "s")
  buf:text(1, 0, paw.util.fit(title, buf.width - 2), "HelpSection")
  for r = 0, rows - 1 do
    local i = r + 1 + self.scroll
    local row = self.rows[i]
    if row then
      local x = 1 + row.depth * 2
      if row.heading then
        buf:text(x, r + 1, paw.util.fit(row.heading, buf.width - x - 1), "Title")
      else
        local at = i == at_row
        if at then buf:fill(0, r + 1, buf.width, 1, " ", "Selected") end
        local text = merge.describe(self.doc, row.conflict.path)
        buf:text(x, r + 1, paw.util.fit(text, buf.width - x - 1), at and "Selected" or "Normal")
      end
    end
  end
  local c = self.order[self.sel]
  local y = buf.height - 6
  buf:text(0, y - 1, string.rep("─", buf.width), "Rule")
  if c then
    local function side(name, label)
      local absent = false
      for _, s in ipairs(c.absent or {}) do
        absent = absent or s == name
      end
      local text = absent and "(not there)" or data.show(c[name], buf.width - 12)
      buf:text(1, y, label, "Dim")
      buf:text(10, y, text, name == "ours" and "Info" or name == "theirs" and "Warn" or "Normal")
      y = y + 1
    end
    side("base", "before")
    side("ours", "ours")
    side("theirs", "theirs")
  end
  buf:text(1, buf.height - 2, "co ours  ct theirs  cb before  cO cT all  j/k move  q", "Dim")
end

local single = {
  co = "ours",
  ct = "theirs",
  cb = "base",
}

function view:on_key(key)
  local combo = self.pending .. key
  if self.pending ~= "" then
    self.pending = ""
    if single[combo] then settle({ self.order[self.sel] }, single[combo]) end
    if combo == "cO" then settle(self.order, "ours") end
    if combo == "cT" then settle(self.order, "theirs") end
  elseif key == "c" then
    self.pending = "c"
  elseif key == "j" or key == "<Down>" then
    self.sel = self.sel + 1
  elseif key == "k" or key == "<Up>" then
    self.sel = self.sel - 1
  elseif key == "q" or key == "<Esc>" then
    paw.ui.close()
  end
  self.sel = paw.util.clamp(self.sel, 1, math.max(1, #self.order))
  api.ui_redraw()
end

function view:on_mouse(event)
  local row = self.rows[event.y + self.scroll]
  if event.kind == "down" and row and row.conflict then
    for i, c in ipairs(self.order) do
      if c == row.conflict then self.sel = i end
    end
  end
  api.ui_redraw()
end

paw.ui.view("projmerge", view)

--- Show the conflicts of the open project; returns how many there are.
function view.open()
  view.sel, view.scroll, view.pending = 1, 0, ""
  refresh()
  local n = #view.order
  if n == 0 then
    paw.notify("the project has no merge conflicts")
    return 0
  end
  paw.ui.open("projmerge", { title = "Merge conflicts", width = 100, height = 24 })
  return n
end

return view
