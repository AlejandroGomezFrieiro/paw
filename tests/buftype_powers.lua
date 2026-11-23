-- A buffer type, and a kind of text buffer, with every power of a view:
-- a cursor per window, keys, motions, text objects and operators said
-- where it is made, what `K` says and its part of the status line. Loaded
-- by tests/suite.lua with its helpers.
local T = ...
local test, eq = T.test, T.eq
local api = paw.api
local L = paw.layout

local W, H = 160, 48
local initial = L.capture()

local function reset()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  L.restore(initial)
  paw.ui.focus("arrange")
end

local keys = T.keys

local function sized(fn)
  local size = api.ui_size
  api.ui_size = function() return W, H end
  local ok, err = xpcall(fn, debug.traceback)
  api.ui_size = size
  if not ok then error(err, 0) end
end

local function status_text()
  local parts = {}
  for _, piece in ipairs(paw.statusline.line(200).left) do
    parts[#parts + 1] = piece[1]
  end
  return table.concat(parts)
end

-- The example of docs/reference/lua-views.md: a tally of marks, one row of cells per
-- buffer, a cursor in each window.
local function define_tally(heard)
  paw.buftype("tally", {
    create = function(target) return { target = target, marks = {} } end,
    render = function(win, canvas, ctx)
      canvas:text(0, 0, "tally " .. ctx.buf.state.target .. " " .. #ctx.buf.state.marks)
    end,
    grid = function(win)
      win.state.col = win.state.col or 0
      return {
        get = function() return 0, win.state.col end,
        set = function(_, col) win.state.col = math.max(0, col) end,
        step = function() return 1 end,
      }
    end,
    keymaps = {
      ["<localleader>m"] = {
        function(ctx) table.insert(ctx.buf.state.marks, ctx.win.state.col) end,
        desc = "Mark the cursor's place",
      },
    },
    motions = {
      ["]t"] = function(ctx) ctx.win.state.col = (ctx.win.state.col or 0) + 4 end,
    },
    textobjects = {
      it = {
        function(ctx) return { kind = "char", r0 = 0, r1 = 0, c0 = ctx.win.state.col, c1 = ctx.win.state.col + 2 } end,
        desc = "Two cells",
      },
    },
    operators = {
      ["g!"] = function(region, ctx) heard[#heard + 1] = { region = region, buf = ctx.buf.state.target } end,
    },
    describe = function(win) return { only = true, title = "Tally", "at " .. win.state.col } end,
    status = function(win) return "tally@" .. (win.state.col or 0) end,
  })
end

local function forget_tally()
  reset()
  paw.ui.views:remove("tally")
  L.types:remove("tally")
  for id, buf in pairs(L.buffers) do
    if buf.type == "tally" then L.buffers[id] = nil end
  end
  for _, map in ipairs(paw.keymap.every()) do
    if map.scope == "tally" then paw.keymap.put(map.mode, map.scope, table.concat(map.keys), nil) end
  end
end

test("a buffer type has a cursor per window, keys, motions, text objects and operators of its own", function()
  T.fresh()
  reset()
  local heard = {}
  define_tally(heard)
  T.after(forget_tally)
  sized(function() keys(":vs tally://a<CR>") end)
  eq(paw.ui.focused, "tally", "its window has the keys")
  local win = L.current()
  keys("]t")
  eq(win.state.col, 4, "its motion moves its cursor")
  keys("<localleader>m")
  eq(L.buf_of(win).state.marks[1], 4, "its key gets the window and the buffer")
  keys("]t")
  keys("g!it")
  eq(#heard, 1, "its operator ran")
  eq(heard[1].region.c0, 8, "on the region of its text object, from the cursor grid(win) gives")
  eq(heard[1].region.c1, 10, "to its end")
  eq(heard[1].buf, "a", "with the buffer")
  keys("v]tg!")
  eq(#heard, 2, "visual mode works through its grid")
  eq(heard[2].region.c0, 8, "from where it started")
  eq(heard[2].region.c1, 12, "to where the motion went")
  eq(win.state.col, 8, "and the cursor goes to the start, as after any operator")
  keys("K")
  eq(T.hover_text():find("at 8", 1, true) ~= nil, true, "K says what describe says: " .. T.hover_text())
  paw.ui.close()
  eq(status_text():find("tally@8", 1, true) ~= nil, true, "the status line shows its part: " .. status_text())
  -- A second window on another buffer keeps a cursor of its own.
  sized(function() keys(":sp tally://b<CR>") end)
  keys("]t")
  eq(L.current().state.col, 4, "a new window has its own cursor")
  eq(win.state.col, 8, "the first window's stays")
  local found = false
  for _, map in ipairs(paw.keymap.every()) do
    if map.scope == "tally" and map.lhs == "<localleader>m" then found = map.desc == "Mark the cursor's place" end
  end
  eq(found, true, "its keys are mapped in its scope, with their descriptions")
end)

test("a kind of text buffer has keys, K and a status of its own, before the text's", function()
  T.fresh()
  reset()
  local heard = {}
  paw.textbuf.kind("shout", {
    pattern = "^paw://shout$",
    read = function() return { { id = 1, text = "one" }, { id = 2, text = "two" } } end,
    format = function(item) return { item.text } end,
    parse = function(text) return { text = text } end,
    plan = function() return {} end,
    keymaps = { ["<localleader>s"] = function(ctx) heard[#heard + 1] = ctx.target end },
    describe = function(ctx) return { only = true, title = "Shout", "a list of " .. ctx.target } end,
    status = function() return "shouting" end,
  })
  T.after(function()
    reset()
    paw.textbuf.kinds:remove("shout")
    paw.keymap.put("n", "textbuf.shout", table.concat(paw.keymap.parse("<localleader>s")), nil)
  end)
  keys(":e paw://shout<CR>")
  eq(paw.ui.focused, "textbuf", "a text buffer")
  keys("<localleader>s")
  eq(heard[1], "paw://shout", "its key, with the buffer's name")
  keys("K")
  eq(T.hover_text():find("a list of paw://shout", 1, true) ~= nil, true, "K: " .. T.hover_text())
  paw.ui.close()
  eq(status_text():find("shouting", 1, true) ~= nil, true, "its status: " .. status_text())
  keys(":e paw://tracks<CR>")
  heard = {}
  keys("<localleader>s")
  eq(#heard, 0, "its keys hold in its own buffers only")
end)
