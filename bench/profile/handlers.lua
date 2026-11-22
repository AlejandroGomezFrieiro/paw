-- The event handlers that run after a key, and the time of each: for the
-- keys `x` (delete a clip), `dd` (delete a track) and their `u`, on the
-- large project of project.lua. Load it in a running paw with the setup of
-- the driver, and read the result at the end:
--   bench/profile/run.sh repeat --keys x,u,dd,u --times 10 \
--     --setup 'dofile("<checkout>/bench/profile/handlers.lua")' \
--     --report 'return paw_bench_handlers()'
-- The result has one line for each key and handler: the keys, the event,
-- the place of the handler in the code, its calls for each press, the mean
-- time of its calls for each press, and its largest call, in ms.
local api = paw.api

-- The keys of the last command that completed: the events of its turn go
-- to it. An undo is named by the command it undoes (`u after dd`).
-- `presses` counts the commands of each.
local current = "(no key)"
local presses = {}
local dispatch = paw.keymap.dispatch
paw.keymap.dispatch = function(key)
  local typed = paw.keymap.pending() .. key
  local results = { dispatch(key) }
  if paw.keymap.pending() == "" then
    current = typed == "u" and "u after " .. current or typed
    presses[current] = (presses[current] or 0) + 1
  end
  return unpack(results)
end

-- Each handler, timed where paw.events calls it (`paw.limit.named` with the
-- name "a handler of `event`"), so that a handler added later counts too:
-- the sum and the largest call for each keys, event and place. The parts of
-- the end of a turn around the handlers count as "(settle)" lines: all of
-- it, the reading of the events from the kernel and the hooks that note
-- them.
local stats = {}
local function add(event, where, ms)
  local key = current .. "\t" .. event .. "\t" .. where
  local s = stats[key]
  if not s then
    s = { keys = current, event = event, where = where, calls = 0, sum = 0, max = 0 }
    stats[key] = s
  end
  s.calls, s.sum, s.max = s.calls + 1, s.sum + ms, math.max(s.max, ms)
end
local places = setmetatable({}, { __mode = "k" })
local function place(fn)
  local where = places[fn]
  if not where then
    local info = debug.getinfo(fn, "S")
    where = string.format("%s:%d", info.short_src:match("paw/.*$") or info.short_src, info.linedefined)
    places[fn] = where
  end
  return where
end
-- The parts of the end of the turn under way that took 0.3 ms or more.
local parts = {}
local function timed(event, where, fn, ...)
  local t = api.now()
  local results = { fn(...) }
  local ms = api.now() - t
  add(event, where, ms)
  if ms >= 0.3 then parts[#parts + 1] = string.format("%s %s %.1f", event, where, ms) end
  return unpack(results, 1, table.maxn(results))
end
local named = paw.limit.named
paw.limit.named = function(name, fn, ...)
  local event = name:match("^a handler of `(.*)`$")
  if not event then return named(name, fn, ...) end
  return named(name, function(...) return timed(event, place(fn), fn, ...) end, ...)
end
-- The ends of a turn over 4 ms: the keys, the time, the Lua heap before
-- and after in KB (less after: the collector ran), and the parts.
local slow_turns = {}
local guard = paw.limit.guard
paw.limit.guard = function(name, fn, ...)
  if name ~= "an event handler" then return guard(name, fn, ...) end
  parts = {}
  local kb, t = collectgarbage("count"), api.now()
  local results = { timed("(settle)", "all of it", guard, name, fn, ...) }
  local ms = api.now() - t
  if ms > 4 and #slow_turns < 20 then
    slow_turns[#slow_turns + 1] = string.format(
      "%s\t(slow turn)\t%.1f ms, heap %d to %d KB\t%s",
      current,
      ms,
      kb,
      collectgarbage("count"),
      table.concat(parts, ", ")
    )
  end
  return unpack(results, 1, table.maxn(results))
end
local take = api.events_take
api.events_take = function() return timed("(settle)", "paw.api.events_take", take) end
local note = paw.hooks.note
paw.hooks.note = function(...) return timed("(settle)", "paw.hooks.note", note, ...) end

--- The result: one tab-separated line for each keys and handler, by keys
--- and the largest sums first (keys, event, place, calls a press, ms a
--- press, largest call ms). A handler under `min_ms` a press (0.05) and
--- under 1 ms a call is left out; a line "(handlers) all" for each keys
--- gives the sum of all of them.
function paw_bench_handlers(min_ms) -- luacheck: ignore 111
  min_ms = min_ms or 0.05
  local list, all = {}, {}
  for _, s in pairs(stats) do
    local n = presses[s.keys] or 1
    list[#list + 1] = { s.keys, s.event, s.where, s.calls / n, s.sum / n, s.max }
    if s.event ~= "(settle)" then
      local a = all[s.keys] or { s.keys, "(handlers)", "all", 0, 0, 0 }
      a[4], a[5], a[6] = a[4] + s.calls / n, a[5] + s.sum / n, math.max(a[6], s.max)
      all[s.keys] = a
    end
  end
  for _, a in pairs(all) do
    list[#list + 1] = a
  end
  table.sort(list, function(a, b)
    if a[1] ~= b[1] then return a[1] < b[1] end
    return a[5] > b[5]
  end)
  local out = {}
  for _, r in ipairs(list) do
    if r[5] >= min_ms or r[6] >= 1 then
      out[#out + 1] = string.format("%s\t%s\t%s\t%.1f\t%.2f\t%.2f", r[1], r[2], r[3], r[4], r[5], r[6])
    end
  end
  for _, line in ipairs(slow_turns) do
    out[#out + 1] = line
  end
  return table.concat(out, "\n")
end
