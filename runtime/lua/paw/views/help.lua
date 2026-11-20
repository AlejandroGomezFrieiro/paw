-- `:help all`: the keys that work where the cursor is, as one long list.
-- `?` shows them in a picker (paw/pick/sources.tl), and `:help` with a
-- topic opens the manual (paw/help.tl).
local api = paw.api

-- `modal` sends every key to `on_key`, bypassing the mappings behind the window.
local view = { scroll = 0, lines = {}, modal = true }
paw.seats.fields("help", view, { "scroll", "lines" }, { scroll = 0, lines = {} })

local function collect(target)
  local lines = {}
  local function section(title, list)
    if #list == 0 then return end
    lines[#lines + 1] = { title = title }
    for _, map in ipairs(list) do
      local what = map.desc or (type(map.rhs) == "string" and map.rhs) or "(function)"
      lines[#lines + 1] = { key = paw.keymap.human(map.lhs), text = what }
    end
    lines[#lines + 1] = {}
  end
  local function of(mode, keep)
    local own, global = {}, {}
    for _, map in ipairs(paw.keymap.list(mode, target)) do
      if not keep or keep(map) then table.insert(map.scope == "global" and global or own, map) end
    end
    return own, global
  end
  local function plain(map) return not map.operator and not map.motion end
  local function join(a, b)
    for _, map in ipairs(b) do a[#a + 1] = map end
    return a
  end
  local own, global = of("n", plain)
  section(target .. " view", own)
  section("everywhere", global)
  section("motions: alone, after an operator, or to stretch a selection", join(of("n", function(map) return map.motion end)))
  section("operators: then a motion or text object, twice for whole rows, or on a selection", join(of("n", function(map) return map.operator end)))
  section("text objects: after an operator, or in a selection", join(of("o", function(map) return map.object end)))
  section("on a selection (v, V, <C-v>)", join(of("x", function(map) return not map.motion and not map.object and not paw.keymap.has("n", map) end)))
  section("insert mode", join(of("i")))
  return lines
end

function view:render(buf)
  local rows = buf.height - 1
  self.scroll = paw.util.clamp(self.scroll, 0, math.max(0, #self.lines - rows))
  for row = 0, rows - 1 do
    local line = self.lines[row + 1 + self.scroll]
    if line and line.title then
      buf:text(1, row, line.title, "HelpSection")
    elseif line and line.key then
      buf:text(2, row, line.key, "HelpKey")
      buf:text(16, row, line.text, "Normal")
    end
  end
  buf:text(1, buf.height - 1, "j/k scroll   any other key closes   `:` runs any command by name", "Dim")
end

function view:on_key(key)
  if key == "j" or key == "<Down>" then
    self.scroll = self.scroll + 1
  elseif key == "k" or key == "<Up>" then
    self.scroll = self.scroll - 1
  elseif key == "<C-d>" or key == "<PageDown>" then
    self.scroll = self.scroll + 10
  elseif key == "<C-u>" or key == "<PageUp>" then
    self.scroll = self.scroll - 10
  else
    paw.ui.close()
  end
  api.ui_redraw()
end

function view:on_mouse(event)
  if event.kind == "scroll_down" then self.scroll = self.scroll + 3 end
  if event.kind == "scroll_up" then self.scroll = self.scroll - 3 end
  api.ui_redraw()
end

paw.ui.view("help", view)

paw.command("help", function(ctx)
  local topic = (ctx.args[1] or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if topic == "all" then
    local target = paw.ui.focused
    view.lines, view.scroll = collect(target), 0
    return paw.ui.open("help", { title = "Keys · " .. tostring(target) .. " · all", width = 76, height = 30 })
  end
  paw.help.open(topic)
end, {
  desc = "The manual: `help` its contents, `help gU` a key, `help :s` a command, `help 'timebind'` an option, `help paw.qf` a module, `help key-rule` a section (Tab completes). `help all` lists every key",
  raw = true,
  complete = function(rest) return paw.help.complete(rest) end,
})

-- A scrollable list of text lines, used for `:messages` and similar. Lines
-- longer than the window go on over the next rows, indented.
local pager = { scroll = 0, lines = {}, modal = true }
paw.seats.fields("pager", pager, { "scroll", "lines" }, { scroll = 0, lines = {} })

--- The first `n` characters of `text` (not bytes), and the rest.
local function split(text, n)
  local i, count = 1, 0
  while i <= #text and count < n do
    i = i + 1
    while i <= #text and text:byte(i) >= 128 and text:byte(i) < 192 do i = i + 1 end
    count = count + 1
  end
  return text:sub(1, i - 1), text:sub(i)
end

local function length(text) return select(2, text:gsub("[^\128-\191]", "")) end

--- `text` cut into rows of at most `width` characters, at a space where
--- there is one after the indent, the rows after the first indented by two.
--- A word longer than the width is cut where the row ends.
local function wrap(text, width)
  local rows = {}
  while length(text) > width do
    local head, tail = split(text, width)
    local at = head:match("^.*() ")
    if tail:sub(1, 1) == " " then
      tail = tail:sub(2)
    elseif at and at > #text:match("^ *") then head, tail = text:sub(1, at - 1), text:sub(at + 1) end
    rows[#rows + 1] = head
    text = "  " .. tail
  end
  rows[#rows + 1] = text
  return rows
end

pager.wrap = wrap

function pager:render(buf)
  local rows = {}
  for _, line in ipairs(self.lines) do
    for _, part in ipairs(wrap(line.text, math.max(8, buf.width - 2))) do rows[#rows + 1] = { text = part, style = line.style } end
  end
  self.scroll = paw.util.clamp(self.scroll, 0, math.max(0, #rows - buf.height))
  for row = 0, buf.height - 1 do
    local line = rows[row + 1 + self.scroll]
    if line then buf:text(1, row, line.text, line.style or "Normal") end
  end
end

pager.on_key, pager.on_mouse = view.on_key, view.on_mouse
paw.ui.view("pager", pager)

--- Show lines of text in a float. Each line is a string or
--- `{ text = ..., style = ... }`. With `opts.bottom`, it opens at the end.
--- `opts.width` and `opts.height` give its size (100 by 30).
function paw.ui.page(title, lines, opts)
  pager.lines, pager.scroll = {}, opts and opts.bottom and math.huge or 0
  for _, line in ipairs(lines) do
    line = type(line) == "table" and line or { text = line }
    for part in (tostring(line.text) .. "\n"):gmatch("([^\n]*)\n") do
      pager.lines[#pager.lines + 1] = { text = part:gsub("\t", "  "), style = line.style }
    end
  end
  paw.ui.open("pager", { title = title, width = opts and opts.width or 100, height = opts and opts.height or 30 })
end
