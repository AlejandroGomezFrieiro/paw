-- Tests of the status line's sections and components (paw/statusline.tl):
-- the line that comes with the program, setting it up, widths, a line per
-- view, components of a script's own, the tab line and the winbar.
-- Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh, after = T.test, T.eq, T.fresh, T.after
local api = paw.api
local sl = paw.statusline

local W, H = 140, 40
local initial = paw.layout.capture()

--- The windows a test opened go when it ends.
local function tidy()
  while paw.ui.float do
    paw.ui.close()
  end
  paw.layout.restore(initial)
  for _, buf in ipairs(paw.layout.buffers_list()) do
    if buf.type == "textbuf" then paw.layout.buf_delete(buf) end
  end
end

local function start()
  fresh()
  after(tidy)
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
  sl.reset()
  after(function() sl.reset() end)
end

--- The text of a line as pieces gave it.
local function text_of(list)
  local out = {}
  for i, piece in ipairs(list) do
    out[i] = piece[1]
  end
  return table.concat(out)
end

local function line(width, which) return sl.line(width or W, which) end

local function screen() return api.ui_snapshot(W, H) end

test("statusline: the status line that comes with the program has the mode first and the project last", function()
  start()
  paw.project.new()
  local l = line()
  local left, right = text_of(l.left), text_of(l.right)
  eq(left:match("^ NORMAL·arrange ") ~= nil, true, "the mode pill first: " .. left)
  eq(left:find("bpm", 1, true) ~= nil, true, "the tempo in it")
  eq(right:find("cpu", 1, true) ~= nil, true, "the engine's load at the right: " .. right)
  eq(screen()[H]:find("NORMAL", 1, true) ~= nil or screen()[H - 1]:find("NORMAL", 1, true) ~= nil, true, "and drawn")
end)

test("statusline: sections hold components by name, function or table, in the order given", function()
  start()
  sl.setup({
    sections = {
      a = { "mode" },
      b = { function() return "bee" end },
      c = { { function() return "see" end, style = "StatusOn" }, { "grid", min = 10 } },
      x = {},
      y = { function() return { { "why", "StatusWarn" } } end },
      z = { function() return "zed" end },
    },
  })
  local l = line()
  local left, right = text_of(l.left), text_of(l.right)
  eq(left:find("bee", 1, true) < left:find("see", 1, true), true, "b before c")
  eq(left:find("see", 1, true) < left:find("grid", 1, true), true, "in the order of the section")
  eq(right:find("why", 1, true) < right:find("zed", 1, true), true, "y before z: " .. right)
  eq(left:find("bpm", 1, true), nil, "what is left out is not there")
  local styles = {}
  for _, piece in ipairs(l.left) do
    styles[piece[1]] = piece[2]
  end
  eq(styles.see, "StatusOn", "a table's style")
  eq(styles.bee, "StatusLine", "a section's own, for plain text")
  eq(sl.customized(), true, "the window is told the line")
end)

test("statusline: a component may have a condition, a narrowest screen and a rank", function()
  start()
  local on = false
  sl.setup({
    sections = {
      a = {},
      b = {},
      c = {
        { function() return "alpha" end, cond = function() return on end },
        { function() return "wide" end, min = 100 },
        { function() return "late" end, rank = 9 },
        { function() return "early" end, rank = 1 },
      },
      x = {},
      y = {},
      z = {},
    },
  })
  eq(text_of(line(140).left):find("alpha", 1, true), nil, "no when its condition is false")
  on = true
  eq(text_of(line(140).left):find("alpha", 1, true) ~= nil, true, "shown once it holds")
  eq(text_of(line(90).left):find("wide", 1, true), nil, "not on a narrow screen")
  eq(text_of(line(140).left):find("wide", 1, true) ~= nil, true, "on a wide one")
  -- Too long for the screen: the highest rank goes first.
  local narrow = text_of(line(16).left)
  eq(narrow:find("late", 1, true), nil, "the highest rank is dropped first: " .. narrow)
  eq(narrow:find("early", 1, true) ~= nil, true, "the lowest stays")
end)

test("statusline: the line is the same for the window and the terminal", function()
  start()
  eq(paw.frontend.state(-1).modal.statusline, nil, "nothing is sent while it is as it comes")
  sl.setup({ sections = { z = { function() return "from a script" end } } })
  local sent = paw.frontend.state(-1).modal.statusline
  eq(type(sent), "table", "the pieces are sent once it is set up")
  eq(text_of(sent.right):find("from a script", 1, true) ~= nil, true, "with what the script put in")
  eq(text_of(sent.left):match("^ NORMAL") ~= nil, true, "and the mode")
end)

test("statusline: a view may have a line of its own, and a float that has the keys another", function()
  start()
  sl.setup({
    sections = { c = { function() return "everywhere" end } },
    views = { pianoroll = { sections = { c = { function() return "in the roll" end } } } },
    inactive_sections = { c = { function() return "float open" end } },
  })
  local function left() return text_of(line().left) end
  eq(left():find("everywhere", 1, true) ~= nil, true, "the usual")
  paw.ui.show("pianoroll")
  paw.ui.focus("pianoroll")
  eq(left():find("in the roll", 1, true) ~= nil, true, "the roll's own")
  eq(left():find("everywhere", 1, true), nil, "instead of the usual")
  paw.ui.hide("pianoroll")
  paw.ui.focus("arrange")
  paw.ui.open("help")
  eq(left():find("float open", 1, true) ~= nil, true, "while a float has the keys")
  paw.ui.close()
end)

test("statusline: an extension adds a component and a script that fails is said, not fatal", function()
  start()
  paw.statusline.component("pulse", { fn = function() return { { "pulse!", "StatusRec" } } end, rank = 2 })
  sl.setup({ sections = { z = { "pulse", function() error("broken on purpose") end, "nothing named so" } } })
  local l = line()
  eq(text_of(l.right):find("pulse!", 1, true) ~= nil, true, "the named component")
  eq(#l.errors, 2, "two things said: " .. paw.inspect(l.errors))
  eq(l.errors[1]:find("broken on purpose", 1, true) ~= nil, true, "what went wrong")
  eq(l.errors[2]:find("nothing named so", 1, true) ~= nil, true, "and what was not found")
  paw.statusline.components:remove("pulse")
end)

test("statusline: a component with a key is called again only when its key changes", function()
  start()
  local key, calls = "one", 0
  paw.statusline.component("counted", {
    key = function() return key end,
    fn = function()
      calls = calls + 1
      return "n" .. calls
    end,
  })
  sl.setup({ sections = { z = { "counted" } } })
  line()
  line()
  line()
  eq(calls, 1, "called once for three lines")
  key = "two"
  line()
  eq(calls, 2, "again when the key changed")
  paw.statusline.components:remove("counted")
end)

test("statusline: the project's name is cut before anything is dropped", function()
  start()
  paw.project.new()
  paw.api.project_set("name", string.rep("a-very-long-name", 4))
  local l = line(70)
  eq(text_of(l.left) .. text_of(l.right) ~= "", true, "something is shown")
  local total = api.str_width(text_of(l.left)) + api.str_width(text_of(l.right))
  eq(total <= 70, true, "it fits: " .. total)
  eq(text_of(l.left):find("NOR", 1, true) ~= nil, true, "the mode stays")
end)

test("statusline: a theme chooses the colours of the mode pill and of each section", function()
  start()
  local function pill() return line().left[1][2] end
  eq(pill(), "StatusMode", "normal mode")
  paw.keymap.set_mode("i")
  eq(pill(), "StatusInsert", "insert mode has its own")
  sl.setup({ theme = "mono" })
  eq(pill(), "StatusMode", "one colour in the mono theme")
  paw.keymap.set_mode("n")
  sl.setup({ theme = { c = "StatusDim" }, sections = { c = { function() return "dimmed" end } } })
  local styles = {}
  for _, piece in ipairs(line().left) do
    styles[piece[1]] = piece[2]
  end
  eq(styles.dimmed, "StatusDim", "a section drawn in a group of the theme's")
end)

test("statusline: the tab line shows what its sections hold, and shows with one tab if asked", function()
  start()
  local function top() return screen()[1] end
  eq(top():find("tabline says", 1, true), nil, "no tab line with one tab")
  sl.setup({ tabline = { always = true, sections = { z = { function() return "tabline says" end } } } })
  eq(top():find("tabline says", 1, true) ~= nil, true, "the row is there with one tab: " .. top())
  eq(top():find("1 ", 1, true) ~= nil, true, "with the tab in it")
  sl.setup({ tabline = false })
  eq(top():find("tabline says", 1, true), nil, "gone when switched off")
end)

test("statusline: a winbar adds to the title bar of the window with the keys, and the others have their own", function()
  start()
  paw.ui.show("mixer")
  paw.textbuf.open("paw://tracks")
  sl.setup({
    winbar = { sections = { x = { function(ctx) return "focused:" .. tostring(ctx.focused) end } } },
    inactive_winbar = { sections = { x = { function() return "elsewhere" end } } },
  })
  local all = table.concat(screen(), "\n")
  eq(all:find("focused:true", 1, true) ~= nil, true, "the window with the keys")
  eq(all:find("elsewhere", 1, true) ~= nil, true, "the others")
  sl.setup({ winbar = false, inactive_winbar = false })
  all = table.concat(screen(), "\n")
  eq(all:find("focused:true", 1, true), nil, "gone when switched off")
end)

test("statusline: `:help statusline` is the page that says how to set it up", function()
  start()
  paw.cmd("help", { "statusline" })
  local buf = paw.layout.buf_of(paw.layout.current())
  eq(buf.name, "help://status-line.md", "in the status line's page")
  local _, _, t, st = paw.textbuf.here()
  eq(t:line(st.row):find("six sections", 1, true) ~= nil, true, "at the paragraph: " .. t:line(st.row))
end)
