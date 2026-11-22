-- The conflicts a merge left in a project file, to settle one by one: ours,
-- theirs or what it was before. Settling writes the file again; a project
-- that is open from that file is read again from it.
local projdiff = require("projdiff")
local merge = projdiff.merge
local data = projdiff.data
local api = paw.api

local view = {
  title = "Merge conflicts",
  modal = true,
  path = nil,
  doc = nil,
  sel = 1,
  scroll = 0,
  pending = "",
}

local function conflicts() return merge.conflicts(view.doc) end

local function write()
  local content = api.project_file_text(view.doc)
  local file = assert(io.open(view.path, "wb"))
  file:write(content)
  file:close()
  local project = api.project_get()
  if project.path == view.path and not project.modified then api.project_load(view.path) end
end

local function settle(list, side)
  if #list == 0 then return end
  local ok, err = pcall(function()
    for _, c in ipairs(list) do
      merge.resolve(view.doc, c, side)
    end
    write()
  end)
  if not ok then return paw.notify("cannot settle: " .. tostring(err):match("[^\n]*"), "error") end
  local left = #conflicts()
  if left == 0 then
    paw.notify("every conflict is settled; `git add` the project to finish the merge")
    paw.ui.close()
  end
end

function view:render(buf)
  local list = conflicts()
  self.sel = paw.util.clamp(self.sel, 1, math.max(1, #list))
  local rows = buf.height - 8
  if self.sel <= self.scroll then self.scroll = self.sel - 1 end
  if self.sel > self.scroll + rows then self.scroll = self.sel - rows end
  buf:text(
    1,
    0,
    paw.util.fit(
      string.format("%s: %d conflict%s", self.path:match("[^/]*$"), #list, #list == 1 and "" or "s"),
      buf.width - 2
    ),
    "HelpSection"
  )
  for r = 0, rows - 1 do
    local c = list[r + 1 + self.scroll]
    if c then
      local at = r + 1 + self.scroll == self.sel
      if at then buf:fill(0, r + 1, buf.width, 1, " ", "Selected") end
      buf:text(1, r + 1, paw.util.fit(merge.describe(self.doc, c.path), buf.width - 2), at and "Selected" or "Normal")
    end
  end
  local c = list[self.sel]
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
  local list = conflicts()
  local combo = self.pending .. key
  if self.pending ~= "" then
    self.pending = ""
    if single[combo] then settle({ list[self.sel] }, single[combo]) end
    if combo == "cO" then settle(list, "ours") end
    if combo == "cT" then settle(list, "theirs") end
  elseif key == "c" then
    self.pending = "c"
  elseif key == "j" or key == "<Down>" then
    self.sel = self.sel + 1
  elseif key == "k" or key == "<Up>" then
    self.sel = self.sel - 1
  elseif key == "q" or key == "<Esc>" then
    paw.ui.close()
  end
  self.sel = paw.util.clamp(self.sel, 1, math.max(1, #conflicts()))
  api.ui_redraw()
end

function view:on_mouse(event)
  if event.kind == "down" and conflicts()[event.y + self.scroll] then self.sel = event.y + self.scroll end
  api.ui_redraw()
end

paw.ui.view("projmerge", view)

--- Show the conflicts of the project file at `path`; returns how many there are.
function view.open(path)
  local doc, err = projdiff.file(path)
  if not doc then
    paw.notify(err, "error")
    return 0
  end
  view.path, view.doc, view.sel, view.scroll, view.pending = path, doc, 1, 0, ""
  local n = #conflicts()
  if n == 0 then
    paw.notify(path:match("[^/]*$") .. " has no merge conflicts")
    return 0
  end
  paw.ui.open("projmerge", { title = "Merge conflicts", width = 100, height = 24 })
  return n
end

return view
