-- The messages of the program: what `paw.notify` says, and what an error
-- that `paw.try` catches says. This module keeps every message and writes
-- it to the log. It is in a low layer (tools/layers.txt), so that each
-- module can give a message. It does not draw: paw/ui.tl sets `show`, and
-- shows the message on the command line.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")

-- Lua 5.1's `unpack`, which Teal's library leaves out, and LuaJIT's
-- `xpcall`, which passes on the arguments after the handler.
local record Lua51
  unpack: function<T>({T}, ?integer, ?integer): T...
  xpcall: function<A, R>(function(...: A): (R...), function(string): (string), ...: A): boolean, R...
end
local lua51 = _G as Lua51

local record M
  --- A message: its text, its level ("info", "warn" or "error") and when
  --- it came (`paw.api.now()`).
  record Message
    text: string
    level: string
    time: number
  end

  --- Every message so far, oldest first: the last 500.
  list: {Message}
  --- Shows a message that came. paw/ui.tl sets it. Nil until then, so a
  --- message before the screen is only kept and logged.
  show: function(message: Message)
end
M.list = {}

-- The most messages that `M.list` keeps.
local KEEP = 500

-- The levels of the log that a message can have: another level is "info"
-- in the log.
local LOG_LEVELS: {string: boolean} = {error = true, warn = true, info = true, debug = true}

--- Give a message. `level` is "info" (the default), "warn" or "error".
function M.notify(text: string, level?: string)
  -- What the kernel refused, as it said it, without the prefix its errors
  -- carry through Lua.
  text, level = (tostring(text):gsub("runtime error: ", "")), level or "info"
  local message: M.Message = {text = text, level = level, time = api.now()}
  M.list[#M.list + 1] = message
  if #M.list > KEEP then
    table.remove(M.list, 1)
  end
  api.log(text, LOG_LEVELS[level] and level or "info")
  -- Without a terminal, the message also goes to stderr.
  if not api.ui_attached() then
    io.stderr:write(text, "\n")
  end
  if M.show then
    M.show(message)
  end
end

--- What a user sees of an error: one line, without the list of calls.
--- The place in the code (`paw/x.lua:12:`) moves to the end, where it does
--- not hide what went wrong. The whole error goes to the log.
function M.failure(err: string): string
  local text = tostring(err)
  local short = text:match("^(.-)\n*stack traceback:") or text
  short = short:gsub("%s+$", "")
  -- A module in Lua or in Teal (`paw/x.tl:12:`).
  local file, line, rest = short:match("^[^\n]-([%w_%-]+%.lua):(%d+): (.*)$")
  if not file then
    file, line, rest = short:match("^[^\n]-([%w_%-]+%.tl):(%d+): (.*)$")
  end
  if file then
    -- An error raised by the code itself (`attempt to index a nil value`)
    -- says where; one raised on purpose says what to do, and that is enough.
    local internal = rest:match("^attempt to ")
      or rest:match("^bad argument")
      or rest:match("^stack overflow")
      or rest:match("^table index is ")
    short = internal and string.format("%s (%s:%s)", rest, file, line) or rest
  end
  return short
end

--- Call a function. If it fails, show the error as a message and do not
--- raise it. Returns true and the results of the function, or false and the error.
--- The message is the first lines of the error (`paw.failure`). The log
--- keeps the list of calls.
function M.try<A, R>(fn: function(...: A): (R...), ...: A): boolean, R...
  local result = {lua51.xpcall(fn, debug.traceback, ...)}
  if not result[1] then
    local err = tostring(result[2])
    local short = M.failure(err)
    if short ~= err then
      api.log(err, "error")
    end
    M.notify(short, "error")
  end
  return (lua51.unpack as function({boolean | R}): (boolean, R...))(result as {boolean | R})
end

return M
