-- Timers: run a function later (`paw.defer`), or again and again
-- (`paw.every`), and stop it (`paw.cancel`). The kernel keeps the clock
-- and fires each timer between keys. This module keeps the timers that
-- wait, so that `paw.ext.unload` stops those of an extension.
--
-- It is in a low layer (tools/layers.txt), so that each module can start
-- a timer. A timer runs against the budget of a callback (paw/limit.tl).
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local limit = require("paw.limit")
local registry = require("paw.registry")

local record M
  --- The timers that wait, by handle (as text): the function that each
  --- runs, with the extension whose files made the function. A timer that
  --- goes from it stops, so the timers of an extension stop when it is
  --- unloaded.
  waiting: registry.Registry<function()>
  wait: function(ms: number)
end

M.waiting = registry.new(
  "timers",
  "timers",
  {
    label = function(): string return "timer" end,
    made = true,
    changed = function(handle: string, fn: function())
      if not fn then
        api.timer_stop(math.tointeger(tonumber(handle)))
      end
    end,
  }
)

--- Run `fn` once, after `ms` milliseconds (or when the current turn ends).
function M.defer(fn: function(), ms?: number): integer
  local handle: integer
  handle = api.timer_start(ms or 0, false, function() M.waiting:remove(tostring(handle)); limit.timed(nil, fn) end)
  M.waiting:put(tostring(handle), fn)
  return handle
end

--- Run `fn` every `ms` milliseconds. Returns a handle for `paw.cancel`.
function M.every(ms: number, fn: function()): integer
  local handle = api.timer_start(ms, true, function() limit.timed(nil, fn) end)
  M.waiting:put(tostring(handle), fn)
  return handle
end

--- Stop a timer: `handle` is what `paw.defer` or `paw.every` returned.
function M.cancel(handle: integer)
  if handle == nil then
    return
  end
  -- A timer that waits stops as it goes from `waiting`. One that
  -- `paw.api.timer_start` started stops here.
  if not M.waiting:remove(tostring(handle)) then
    api.timer_stop(handle)
  end
end

--- Let `ms` milliseconds pass while timers fire and events are delivered, as
--- they do between key presses. A script run with `-l` is one long turn in
--- which neither happens unless it waits like this.
M.wait = api.wait

return M
