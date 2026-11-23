-- The command-line window, as Vim's: the history of a prompt as a text
-- buffer in a window at the bottom. The user edits a line with the keys of
-- the text and runs it with Enter.
--
--   q:   the history of `:`        q/   the history of `/`
--   Ctrl-f in a prompt: the history of that prompt, with the text typed so
--   far on the last line
--
-- The window holds the prompt that opened it (`paw.views.cmdline`'s
-- `detach`). Enter goes back to the window that was in front and runs the
-- line through that prompt (`resume`), so the line goes in the history as a
-- line typed there does. A change to the lines does not change the history.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local type contracts = require("paw.contracts")
local type TextbufModule = require("paw.textbuf")

-- The global `paw` (runtime/types/paw.d.tl): no module of the global
-- requires this one, so it sees the global's types.
local layout = paw.layout
local textbuf = paw.textbuf

--- A prompt of paw/views/cmdline.lua, as far as this module reads it.
local record Prompt
  prompt: string
  history_name: string
end

--- paw/views/cmdline.lua (Lua), as far as this module calls it.
local record Cmdline
  detach: function(): Prompt, string
  resume: function(prompt: Prompt, line: string)
  histories: function(): {string: {string}}
end
local cmdline = (require as function(string): Cmdline)("paw.views.cmdline")

--- paw/keymap.lua (Lua), as far as this module calls it.
local record KeymapPart
  normal: function(keys: string): boolean
end

--- The window that is open: the prompt that it runs a line through, the
--- text typed in the prompt (the last line), the window, and the window
--- that was in front. Nil when no window is open.
local record Session
  prompt: Prompt
  typed: string
  win: integer
  from: integer
end
local session: Session

--- How many rows the window takes, as Vim's `cmdwinheight`.
local HEIGHT = 7

local record HistoryLine is contracts.TextItem
  text: string
end

local record M
  edit: function()
  open: function(key: string)
end

--- The window of the session, if it is still on screen.
local function session_window(): contracts.Window
  return session and layout.get(session.win) as contracts.Window or nil
end

--- Close the window, and give the keyboard back to the window that was in
--- front. Returns the session that it ends.
local function close(): Session
  local s = session
  session = nil
  local win = s and layout.get(s.win)
  if win then
    layout.close(win)
  end
  local from = s and layout.get(s.from)
  if from then
    layout.enter(from)
  end
  api.ui_redraw()
  return s
end

--- Run the line under the cursor through the prompt of the session.
local function run(line: string)
  local s = close()
  if not s then
    return paw.notify("this history is not in a command-line window: open it with `q:` or `q/`", "warn")
  end
  -- An empty line runs nothing, as an empty command line does.
  if line:match("%S") then
    cmdline.resume(s.prompt, line)
  end
end

textbuf.kind(
  "history",
  {
    pattern = "^paw://history/(.+)$",
    gutter = false,
    static = true,
    scratch = "the history is not written: Enter runs the line under the cursor, `:q` closes the window",
    read = function(ctx?: contracts.TextContext): {HistoryLine}, string
      local items: {HistoryLine} = {}
      for i, line in ipairs(cmdline.histories()[ctx.args[1]] or {}) do
        items[i] = {id = i, text = line}
      end
      -- The last line is the text typed so far, empty after `q:`.
      items[#items + 1] = {id = #items + 1, text = session and session.typed or ""}
      return items
    end,
    format = function(item: HistoryLine): {string} return {item.text} end,
    parse = function(): {string: string}, string return {} end,
    title = function(ctx?: contracts.TextContext): string
      local prompt = session and session.prompt.prompt or ctx.args[1]
      return "History of " .. prompt
    end,
    hint = "Enter runs the line · :q or Ctrl-c closes",
    open = function(_?: contracts.TextContext, _?: contracts.TextLine<{string: string}>, text?: string) run(text) end,
    keymaps = {["<C-c>"] = {function() close() end, desc = "Close the window without running a line"}},
  }
)

--- Open the window on the history of the prompt that is open, with the
--- text typed so far on the last line (`Ctrl-f` in a prompt).
function M.edit()
  if session_window() then
    return paw.notify("the command-line window is open already", "warn")
  end
  local from = layout.current()
  local prompt, typed = cmdline.detach()
  if not prompt then
    return paw.notify("no prompt with a history is open: `q:` and `q/` open the window", "warn")
  end
  session = {prompt = prompt, typed = typed, from = from and from.id}
  local buf = layout.buf_create("textbuf", "paw://history/" .. prompt.history_name)
  textbuf.reload(buf as TextbufModule.TextBuffer)
  local win, why = layout.split({view = "textbuf", buf = buf.id})
  if not win then
    session = nil
    return paw.notify("no room for the command-line window: " .. why, "warn")
  end
  session.win = win.id
  -- Along the whole bottom of the tab, a few rows high.
  layout.move_to_edge("J")
  win.size = HEIGHT
  -- The cursor on the last line, at the end of the text typed.
  local _, _, text, cursor = textbuf.here()
  cursor.row = text:count()
  cursor.col = math.max(0, text:len(cursor.row) - 1)
  api.ui_redraw()
end

--- Open the window on the history of the prompt that `key` opens (`:` or
--- `/`), with an empty last line (`q:` and `q/`).
function M.open(key: string)
  if session_window() then
    return paw.notify("the command-line window is open already", "warn")
  end
  local keymap = paw.keymap as KeymapPart
  keymap.normal(key)
  M.edit()
end

return M
