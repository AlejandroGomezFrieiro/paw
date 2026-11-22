-- The event list: every note and controller move of the clip open in the
-- piano roll, a row each in time order, with its time, kind, which note or
-- controller, value and length; each cell is changed in place. In the
-- terminal it floats over the screen (`E` in the piano roll,
-- `:notes.list`); the window opens it in a window of its own.
local api = paw.api
local util = paw.util
local controls = require("paw.controls")

-- `modal` sends every key to `on_key`, bypassing the mappings behind it.
local view = { title = "Events", row = 1, column = 4, scroll = 0, modal = true }
paw.seats.fields("eventlist", view, { "row", "column", "scroll" }, { row = 1, column = 4, scroll = 0 })

local HEADINGS = { time = "Time", kind = "Kind", which = "Which", value = "Value", length = "Length" }
local WIDTHS = { time = 11, kind = 11, which = 10, value = 11, length = 8 }

function view:clip() return paw.ui.views.pianoroll:clip() end

--- The rows of the clip open in the piano roll, with the cursor kept on one.
function view:rows()
  local clip = self:clip()
  local rows = clip and controls.rows(clip.id) or {}
  self.row = util.clamp(self.row, 1, math.max(1, #rows))
  self.column = util.clamp(self.column, 1, #controls.columns)
  return rows, clip
end

function view:render(buf, ctx)
  local rows, clip = self:rows()
  local w, h = buf.width, buf.height
  buf:fill(0, 0, w, h, " ", "Normal")
  if not clip then
    buf:text(1, 1, "No clip in the piano roll.", "Empty")
    return
  end
  local x = 1
  for _, name in ipairs(controls.columns) do
    buf:text(x, 0, HEADINGS[name], "HelpSection")
    x = x + WIDTHS[name] + 1
  end
  local room = h - 3
  if self.row <= self.scroll then self.scroll = self.row - 1 end
  if self.row > self.scroll + room then self.scroll = self.row - room end
  self.scroll = util.clamp(self.scroll, 0, math.max(0, #rows - room))
  for i = 1, room do
    local index = i + self.scroll
    local row = rows[index]
    if not row then break end
    local y = i
    local here = index == self.row
    if here then buf:fill(0, y, w, 1, " ", "Selected") end
    local cells = controls.cells(clip.id, row)
    x = 1
    for c, name in ipairs(controls.columns) do
      local style = here and (c == self.column and ctx.focused and "RollCursor" or "Selected")
        or name == "kind" and (row.kind == "note" and "Bright" or "Accent")
        or "Normal"
      buf:text(x, y, util.fit(cells[name], WIDTHS[name]), style)
      x = x + WIDTHS[name] + 1
    end
  end
  if #rows == 0 then buf:text(1, 1, "The clip has no notes or controller moves.", "Empty") end
  buf:text(1, h - 1, "j/k h/l move   Enter change   x delete   a add a move   q close", "Dim")
end

--- Ask for a new text for the cell under the cursor, and set it.
function view:edit()
  local rows, clip = self:rows()
  local row = rows[self.row]
  if not row then return end
  local name = controls.columns[self.column]
  local current = controls.cells(clip.id, row)[name]
  paw.ui.input({ prompt = HEADINGS[name] .. ": ", text = current }, function(text)
    local ok, err = pcall(controls.edit, clip.id, row, name, text)
    if not ok then return paw.notify(tostring(err), "warn") end
    api.ui_redraw()
  end)
end

--- Ask what kind of move to add at the time of the row under the cursor:
--- `cc 74`, `bend`, `pressure` or `program`.
function view:add()
  local rows, clip = self:rows()
  if not clip then return end
  local at = rows[self.row] and rows[self.row].start or 0
  paw.ui.input({ prompt = "Add a move (cc 74, bend, pressure, program): ", text = "cc 1" }, function(text)
    local kind, number = text:match("^%s*(%a+)%s*(%d*)%s*$")
    if not (kind == "cc" or kind == "bend" or kind == "pressure" or kind == "program") then
      return paw.notify("a move is cc and its number, bend, pressure or program", "warn")
    end
    local made = controls.add(clip.id, at, kind, tonumber(number))
    for i, r in ipairs(controls.rows(clip.id)) do
      if r.control and r.start == made.start and r.control.type == made.type then self.row = i end
    end
    self.column = 4
    api.ui_redraw()
  end)
end

function view:remove()
  local rows, clip = self:rows()
  local row = rows[self.row]
  if row then controls.remove_row(clip.id, row) end
  api.ui_redraw()
end

function view:on_key(key)
  if key == "j" or key == "<Down>" then
    self.row = self.row + 1
  elseif key == "k" or key == "<Up>" then
    self.row = self.row - 1
  elseif key == "h" or key == "<Left>" or key == "<S-Tab>" then
    self.column = self.column - 1
  elseif key == "l" or key == "<Right>" or key == "<Tab>" then
    self.column = self.column + 1
  elseif key == "<C-d>" or key == "<PageDown>" then
    self.row = self.row + 10
  elseif key == "<C-u>" or key == "<PageUp>" then
    self.row = self.row - 10
  elseif key == "g" then
    self.row = 1
  elseif key == "G" then
    self.row = math.huge
  elseif key == "<CR>" or key == "i" or key == "c" then
    return self:edit()
  elseif key == "x" or key == "<Del>" or key == "d" then
    return self:remove()
  elseif key == "a" or key == "o" then
    return self:add()
  elseif key == "u" then
    paw.undo()
  elseif key == "<C-r>" then
    paw.redo()
  elseif key == ":" then
    return paw.commands.exec("cmdline")
  elseif key == "q" or key == "<Esc>" then
    return paw.ui.close()
  end
  self:rows()
  api.ui_redraw()
end

function view:on_mouse(event)
  if event.kind == "scroll_down" then self.row = self.row + 3 end
  if event.kind == "scroll_up" then self.row = self.row - 3 end
  if (event.kind == "down" or event.kind == "double") and event.y >= 1 then
    self.row = self.scroll + event.y
    local x = 1
    for c, name in ipairs(controls.columns) do
      if event.x >= x - 1 then self.column = c end
      x = x + WIDTHS[name] + 1
    end
    self:rows()
    if event.kind == "double" then return self:edit() end
  end
  api.ui_redraw()
end

paw.ui.view("eventlist", view)
return view
