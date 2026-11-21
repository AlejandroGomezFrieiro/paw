-- The quickfix list's window (paw/qf.tl): a buffer type, so that `:copen`
-- docks it along the bottom, `:vs quickfix` shows it beside, `:lopen` shows
-- a window's location list below it. A row for each entry: its level, where
-- it is, what it says and who said it. Enter goes there; the graphical
-- frontend shows it in a window of its own (`:qf.window`, or More).
local api = paw.api
local util = paw.util
local layout = paw.layout
local qf = paw.qf

local M = {}

-- The window a graphical frontend draws the list in.
local loose

local function stack_of(win)
  local buf = win and layout.buf_of(win)
  if buf and type(buf.target) == "number" then return qf.loc_stack(buf.target, true) end
  return qf.stack()
end

--- The list window the keyboard is in: the current window, or the one a
--- graphical frontend shows.
function M.current()
  local win = layout.current()
  if win and win.view == "qflist" then return win end
  if paw.ui.focused == "qflist" and loose then return loose end
end

local function state(win)
  local s = win.state
  s.row, s.top = s.row or 1, s.top or 0
  return s
end

local LETTER = { "E", "W", "I", "H" }
local STYLE = { "DiagnosticError", "DiagnosticWarn", "DiagnosticInfo", "DiagnosticHint" }

local function render(win, canvas, ctx)
  local stack = stack_of(win)
  local list = qf.current(stack)
  local s = state(win)
  local entries = list and list.entries or {}
  -- The cursor starts on the current entry.
  if not s.list or s.list ~= (list and list.id) then
    s.list, s.row, s.top = list and list.id, list and math.max(1, list.idx) or 1, 0
  end
  s.row = util.clamp(s.row, 1, math.max(1, #entries))
  local n = qf.count(list)
  local counts = {}
  for i, word in ipairs({ "error", "warning", "info", "hint" }) do
    if n[word] > 0 then counts[#counts + 1] = LETTER[i] .. n[word] end
  end
  local buf = layout.buf_of(win)
  local name = type(buf and buf.target) == "number" and "Location list" or "Quickfix list"
  local body = paw.ui.titlebar(canvas, {
    name = name .. (list and list.title ~= "" and (" · " .. list.title) or ""),
    context = list and string.format("%d entr%s%s", n.total, n.total == 1 and "y" or "ies", #counts > 0 and ("  " .. table.concat(counts, " ")) or "") or "",
    right = #stack.lists > 1 and string.format("list %d of %d", stack.at, #stack.lists) or nil,
    focused = ctx.focused,
  })
  local w, h = body.width, body.height
  if #entries == 0 then
    body:text(2, 0, list and "No entries." or "No lists yet: problems come here, and `:cdiag` puts the diagnostics here.", "Empty")
    return
  end
  if s.row <= s.top then s.top = s.row - 1 end
  if s.row > s.top + h then s.top = s.row - h end
  s.top = util.clamp(s.top, 0, math.max(0, #entries - h))
  local g = paw.draw.g
  local where_w = util.clamp(math.floor(w / 4), 10, 28)
  local source_w = 0
  for _, e in ipairs(entries) do
    if e.source then source_w = math.max(source_w, api.str_width(e.source) + 3) end
  end
  source_w = math.min(source_w, 18)
  for y = 0, h - 1 do
    local i = s.top + y + 1
    local e = entries[i]
    if not e then break end
    local here = i == s.row
    local base = here and ctx.focused and "Selected" or "Normal"
    if here and ctx.focused then body:fill(0, y, w, 1, " ", "Selected") end
    if i == list.idx then body:text(0, y, g.cursor, here and ctx.focused and "SelectedMark" or "Accent") end
    if e.severity then body:text(2, y, LETTER[e.severity], STYLE[e.severity]) end
    local x = 4
    body:text(x, y, util.fit(qf.where(e), where_w), e.fixed and "Dim" or (here and ctx.focused and "Selected" or "Bright"))
    x = x + where_w + 1
    local room = w - x - source_w - 1
    local text = e.text .. (e.fix and not e.fixed and ("  " .. g.out .. " " .. qf.fix_title(e)) or "") .. (e.fixed and "  (fixed)" or "")
    if room > 0 then body:text(x, y, util.fit(text, room), e.fixed and "Dim" or base) end
    if source_w > 0 and e.source then body:text(w - source_w + 1, y, util.fit("[" .. e.source .. "]", source_w - 1), "Dim") end
  end
end

-- The buffer type ----------------------------------------------------------------------

layout.buftype("qflist", {
  listed = false,
  -- `quickfix` (and `qf`) name the quickfix list's buffer; a location list's is a window's number.
  claims = function(name) return name == "quickfix" or name == "qf" end,
  bufname = function(target) return type(target) == "number" and ("loclist " .. target) or "quickfix" end,
  title = function(buf)
    local list = qf.current(type(buf.target) == "number" and qf.loc_stack(buf.target, true) or qf.stack())
    return (type(buf.target) == "number" and "Location list" or "Quickfix list") .. (list and list.title ~= "" and (" · " .. list.title) or "")
  end,
  create = function() return {} end,
  render = render,
  window = function()
    if not loose then loose = layout.leaf("qflist", { buf = layout.buf_create("qflist", "quickfix").id }) end
    return loose
  end,
})
local view = paw.ui.views.qflist
view.title = "Quickfix list"
-- The graphical frontend lists it among the views it can open (More).
view.window = nil

local function move(by)
  local win = M.current()
  if not win then return end
  local s = state(win)
  local list = qf.current(stack_of(win))
  s.row = util.clamp(s.row + by, 1, math.max(1, list and #list.entries or 1))
  api.ui_redraw()
end

--- Go to the entry under the cursor of the list window, making it the
--- current one: the view that shows it gets the keyboard.
function M.choose(row)
  local win = M.current()
  if not win then return end
  local s = state(win)
  qf.jump(row or s.row, stack_of(win))
end

local function fix_here()
  local win = M.current()
  if not win then return end
  local list = qf.current(stack_of(win))
  local e = list and list.entries[state(win).row]
  if not e then return end
  if not e.fix then return paw.notify("this entry has no fix", "warn") end
  if qf.fix({ e }) > 0 then paw.notify("made: " .. qf.fix_title(e)) end
end

function view:on_mouse(event)
  local win = (event.win and layout.get(event.win)) or M.current()
  if not win then return end
  local step = paw.mouse.wheel(event)
  if step then return move(step * 3) end
  if (event.kind == "down" or event.kind == "double") and event.y >= 1 then
    if layout.current() ~= win and win ~= loose then layout.enter(win) end
    local s = state(win)
    s.row = s.top + event.y
    if event.kind == "double" then return M.choose() end
    api.ui_redraw()
  end
end

local map = paw.keymap.set
local function qmap(lhs, rhs, desc, opts) map(lhs, rhs, paw.util.merge({ view = "qflist", desc = desc }, opts)) end
-- Moving keys are motions, as in every view (docs/reference/key-rule.md).
local motion = { motion = true }
qmap("j", function(ctx) move(ctx.count or 1) end, "The next entry", motion)
qmap("k", function(ctx) move(-(ctx.count or 1)) end, "The entry above", motion)
qmap("<Down>", function(ctx) move(ctx.count or 1) end, "The next entry", motion)
qmap("<Up>", function(ctx) move(-(ctx.count or 1)) end, "The entry above", motion)
qmap("<C-d>", function() move(10) end, "Ten entries down")
qmap("<C-u>", function() move(-10) end, "Ten entries up")
qmap("gg", function(ctx) move(-math.huge) if ctx.count then move(ctx.count - 1) end end, "The first entry", motion)
qmap("G", function() move(math.huge) end, "The last entry", motion)
qmap("<CR>", function() M.choose() end, "Go to the entry: the view that shows it gets the keyboard")
qmap("<leader>la", fix_here, "Make the entry's fix, as one undo step")
qmap("q", function()
  local win = M.current()
  if win == loose then return paw.ui.close() end
  if win and not layout.close(win) then paw.notify("the last window does not close", "warn") end
end, "Close the window")

paw.ui.keybar.set("qflist", "n", {
  { "j", "next" }, { "k", "previous" }, { "<CR>", "jump" }, { "<leader>la", "fix" }, { "q", "close" }, { "?", "keys" },
})

paw.command("qf.window", function()
  paw.canvas.open_view("qflist", { title = "Quickfix list", width = 760, height = 300 })
end, { desc = "Show the quickfix list in a window of its own, in the graphical frontend" })

return M
