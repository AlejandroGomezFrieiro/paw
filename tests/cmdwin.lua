-- Tests of the command-line window (paw/cmdwin.tl): `q:`, `q/` and Ctrl-f
-- in a prompt show a history as a text buffer, and Enter runs a line.
local T = ...
local test, eq, fresh, keys = T.test, T.eq, T.fresh, T.keys
local L = paw.layout
local cmdline = require("paw.views.cmdline")

local initial = L.capture()

-- What `:test.say` was given, in order.
local said

local function start()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  L.restore(initial)
  paw.ui.focus("arrange")
  -- Each test starts with empty histories, and puts the old ones back.
  local kept = {}
  for _, name in ipairs({ "cmdline", "search" }) do
    kept[name] = { unpack(cmdline.histories()[name] or {}) }
    cmdline.set_history(name, {})
  end
  said = {}
  paw.command("test.say", function(ctx) said[#said + 1] = table.concat(ctx.args, " ") end, { desc = "test" })
  T.after(function()
    paw.commands.specs:remove("test.say")
    for name, lines in pairs(kept) do
      cmdline.set_history(name, lines)
    end
    for _, buf in ipairs(L.buffers_list()) do
      if buf.type == "textbuf" then L.buf_delete(buf) end
    end
    L.restore(initial)
  end)
end

--- The lines of the text buffer in front, or nil when it is not one.
local function lines()
  local buf = paw.textbuf.buf()
  if not buf then return nil end
  local out = {}
  for i, l in ipairs(buf.state.text.lines) do
    out[i] = l.text
  end
  return out
end

local function history(name) return table.concat(cmdline.histories()[name], "|") end

test("q: opens the command-line window on the history of :, and Enter runs a line in the window in front", function()
  start()
  keys(":test.say 1<CR>:test.say 2<CR>")
  keys("q:")
  eq(table.concat(lines(), "|"), "test.say 1|test.say 2|", "the history, oldest first, and an empty last line")
  keys("k<CR>")
  eq(table.concat(said, "|"), "1|2|2", "Enter ran the line under the cursor")
  eq(lines(), nil, "and closed the window")
  eq(paw.ui.focused, "arrange", "the window in front has the keyboard again")
end)

test("a line edited in the command-line window runs as edited and goes in the history", function()
  start()
  keys(":test.say 1<CR>q:k$cwedited<Esc><CR>")
  eq(said[#said], "edited", "the edited line ran")
  eq(history("cmdline"), "test.say 1|test.say edited", "the line run is added to the history")
end)

test(":q and Ctrl-c close the command-line window without running a line or changing the history", function()
  start()
  keys(":test.say 1<CR>")
  keys("q:k$cwedited<Esc>:q<CR>")
  eq(lines(), nil, ":q closed the window with its changes")
  keys("q:<C-c>")
  eq(lines(), nil, "Ctrl-c closed it")
  eq(table.concat(said, "|"), "1", "nothing ran")
  eq(history("cmdline"), "test.say 1|q", "the edit is not in the history; the `:q` typed is")
end)

test("q/ opens the command-line window on the searches, and Enter searches a line", function()
  start()
  paw.add_part({ name = "Bass" })
  paw.add_part({ name = "Drums" })
  keys("/Bass<CR>/Drums<CR>")
  eq(paw.keymap.search_text, "Drums", "the last search")
  keys("q/")
  eq(table.concat(lines(), "|"), "Bass|Drums|", "the searches, oldest first")
  keys("kk<CR>")
  eq(lines(), nil, "the window closed")
  eq(paw.keymap.search_text, "Bass", "Enter searched the line")
  eq(paw.cursor.part().name, "Bass", "and the cursor went to it")
end)

test("Ctrl-f in the command line opens the command-line window with the text typed so far on the last line", function()
  start()
  keys(":test.say 1<CR>:test.say ty<C-f>")
  eq(cmdline.state(), nil, "the prompt gave way to the window")
  eq(table.concat(lines(), "|"), "test.say 1|test.say ty", "the typed text is the last line")
  keys("Aped<Esc><CR>")
  eq(said[#said], "typed", "Enter ran the line")
end)

test("qa still records a macro in register a, though q: opens the command-line window", function()
  start()
  T.after(function()
    if paw.keymap.recording() then keys("q") end
  end)
  keys("qa")
  eq(paw.keymap.recording(), "a", "recording into a")
  keys("q")
  eq(paw.keymap.recording(), nil, "q stopped it")
end)
