-- The start page: what an empty window shows (`:vnew`, `:tabnew`, a tab
-- left with no view). It is a buffer type, "empty", with a buffer for each
-- such window. It shows the transport, the recent projects (Enter opens
-- the one under the cursor) and how to show a view here. Nothing in paw
-- needs a window of a particular view: this page is what there is when a
-- window shows nothing.
local api = paw.api
local util = paw.util
local layout = paw.layout

local M = {}

-- The recent projects, read again at most each two seconds: the page is
-- drawn on every tick while the song plays.
local recent, read_at = {}, -math.huge

local function projects()
  if not paw.recent then return {} end
  if api.now() - read_at > 2000 then
    recent, read_at = paw.recent.list(), api.now()
  end
  return recent
end

-- A project saved or opened is at the top of the list at once.
paw.on("project.saved", function() read_at = -math.huge end)
paw.on("project.loaded", function() read_at = -math.huge end)

local function home(path)
  local dir = os.getenv("HOME")
  if dir and dir ~= "" and path:sub(1, #dir + 1) == dir .. "/" then return "~" .. path:sub(#dir + 1) end
  return path
end

-- What to type to show something here, each with what it shows.
local HINTS = {
  { ":e arrange", "the arrange view: the parts in time" },
  { ":e roll://riff", "the clip riff in the piano roll (or its number, roll://7)" },
  { ":e mixer", "the mixer; also devices, session, and the views of extensions" },
  { ":vs <view>", "a view beside this window (:sp <view> below it)" },
  { ":tabnew <view>", "a new tab that shows a view" },
  { ":e song", "open a project" },
  { ":ls", "the buffers; :close closes this window, :only closes the others" },
}

local function state(win)
  local s = win.state
  s.row = s.row or 1
  return s
end

--- Where each part of the page is, in the rows of its body: the first row
--- of the projects, and how many show.
local function places(h, n)
  local first = 4
  local room = math.max(0, h - first - #HINTS - 3)
  return first, math.min(n, math.max(n > 0 and 1 or 0, room))
end

local function render(win, canvas, ctx)
  local body = paw.ui.titlebar(canvas, { name = "Start", context = "an empty window", focused = ctx.focused })
  local w, h = body.width, body.height
  local s = state(win)
  local p, t = api.project_get(), api.transport_get()
  local at = paw.time.format(paw.time.local_beat(t.position))
  local where = t.playing and ("playing at " .. at) or ("stopped at " .. at)
  local line = string.format("%s  ·  %g bpm %d/%d  ·  %s", p.name, p.tempo, p.sig_num, p.sig_den, where)
  body:text(2, 1, util.fit(line, math.max(1, w - 4)), "Bright")
  local list = projects()
  s.row = util.clamp(s.row, 1, math.max(1, #list))
  local first, shown = places(h, #list)
  body:text(2, first - 1, "Recent projects", "Title")
  if #list == 0 then
    body:text(4, first, util.fit("None yet: :e song opens one, :w song saves this one.", math.max(1, w - 6)), "Empty")
    shown = 1
  end
  local top = math.max(0, s.row - shown)
  for i = 1, #list > 0 and shown or 0 do
    local entry = list[top + i]
    if not entry then break end
    local y = first + i - 1
    local here = top + i == s.row
    if here and ctx.focused then body:fill(2, y, w - 4, 1, " ", "Selected") end
    local style = here and ctx.focused and "Selected" or "Normal"
    body:text(2, y, here and paw.draw.g.cursor or " ", here and ctx.focused and "SelectedMark" or "Accent")
    local name = util.fit(entry.name or "", 24)
    body:text(4, y, name, here and ctx.focused and "Selected" or "Bright")
    body:text(30, y, util.fit(home(entry.path), math.max(1, w - 32)), style)
  end
  local y = first + shown + 1
  body:text(2, y, "Show something here", "Title")
  for i, hint in ipairs(HINTS) do
    if y + i >= h then break end
    body:text(4, y + i, hint[1], "HintKey")
    body:text(22, y + i, util.fit(hint[2], math.max(1, w - 24)), "Empty")
  end
end

layout.buftype("empty", {
  listed = false,
  -- Numbered among the empty windows there are now, the lowest free
  -- number first, so a long session does not climb to `[No Name 14]`.
  bufname = function(_, buf)
    local taken = {}
    for _, other in pairs(layout.buffers) do
      if other ~= buf and other.type == "empty" then taken[other.name] = true end
    end
    local name, n = "[No Name]", 1
    while taken[name] do
      n = n + 1
      name = "[No Name " .. n .. "]"
    end
    return name
  end,
  title = function() return "Start" end,
  render = render,
  on_mouse = function(win, event)
    local list = projects()
    local step = paw.mouse.wheel(event)
    local s = state(win)
    if step then
      s.row = util.clamp(s.row + step, 1, math.max(1, #list))
      return api.ui_redraw()
    end
    if event.kind ~= "down" and event.kind ~= "double" then return end
    -- The body starts under the title row.
    local first, shown = places((event.h or 0) - 1, #list)
    local row = event.y - 1 - first
    if row < 0 or row >= shown then return end
    s.row = math.max(0, s.row - shown) + row + 1
    if event.kind == "double" then return M.open(win) end
    api.ui_redraw()
  end,
  keymaps = {
    ["<CR>"] = { function(ctx) M.open(ctx.win) end, desc = "Open the recent project under the cursor" },
  },
  motions = {
    j = { function(ctx) M.move(ctx.win, ctx.count or 1) end, desc = "The next recent project" },
    k = { function(ctx) M.move(ctx.win, -(ctx.count or 1)) end, desc = "The recent project above" },
  },
})

--- Move the cursor of a start page `by` projects.
function M.move(win, by)
  if not win then return end
  local s = state(win)
  s.row = util.clamp(s.row + by, 1, math.max(1, #projects()))
  api.ui_redraw()
end

--- Open the recent project under the cursor of a start page.
function M.open(win)
  if not win then return end
  local entry = projects()[state(win).row]
  if not entry then return paw.notify("no recent projects yet: `:e song` opens one", "warn") end
  if not paw.project.guard("open") then return end
  paw.recent.open(entry.path)
end

if paw.ui.keybar then
  paw.ui.keybar.set("empty", "n", { { "j", "next" }, { "k", "previous" }, { "<CR>", "open" }, { "?", "keys" } })
end

return M
