-- Small helpers with no dependencies on the rest of the runtime.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")

-- What this module reads of `paw`, which paw/init.lua makes. A module of the
-- runtime in Teal does not see the global `paw`: runtime/types/paw.d.tl
-- declares it from these modules.
local record Draw
  g: {string: string}
end
local record Paw
  draw: Draw
end
local paw = (_G as {string: Paw}).paw

local record M
  --- Data as Lua holds it: text, a number, a boolean, or a table of them.
  type Data = string | number | boolean | {Data: Data}

  --- An entry of a list that `by_order` sorts: its key and its place.
  --- `paw.contracts.OwnedEntry` is one.
  interface Ordered
    key: string
    order: integer
  end

  FADER_MIN: number
  FADER_MAX: number
end

local type Data = M.Data

local function sorted_keys(t: {Data: Data}): {Data}
  local keys: {Data} = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(
    keys,
    function(a: Data, b: Data): boolean
      if a is number and b is number then
        return a < b
      end
      if a is string and b is string then
        return a < b
      end
      return tostring(a) < tostring(b)
    end
  )
  return keys
end

--- Render any value as readable Lua-like text.
function M.inspect<T>(value: T, indent?: string, seen?: {Data: boolean}): string
  indent, seen = indent or "", seen or {}
  if value is string then
    return string.format("%q", value)
  end
  if not (value is {Data: Data}) then
    return tostring(value)
  end
  local t = value as {Data: Data}
  if seen[t] then
    return "<cycle>"
  end
  seen[t] = true
  if next(t) == nil then
    return "{}"
  end
  local parts, inner = {}, indent .. "  "
  local list = t as {Data}
  local n = #list
  for i = 1, n do
    parts[#parts + 1] = inner .. M.inspect(list[i], inner, seen)
  end
  for _, k in ipairs(sorted_keys(t)) do
    if not (k is number and k >= 1 and k <= n and k % 1 == 0) then
      local key = k is string and k:match("^[%a_][%w_]*$") and k or "[" .. M.inspect(k) .. "]"
      parts[#parts + 1] = inner .. key .. " = " .. M.inspect(t[k], inner, seen)
    end
  end
  seen[t] = nil
  return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

--- `v`, kept between `lo` and `hi`.
function M.clamp(v: number, lo: number, hi: number): number
  if v < lo then
    return lo
  end
  if v > hi then
    return hi
  end
  return v
end

--- A path as typed, with `~` at its start for the home folder, as a shell
--- reads it: `~/mix.wav`. Every command that takes a file name reads it so.
function M.expand_path(path: string): string
  if not (path is string) then
    return path
  end
  if path == "~" or path:sub(1, 2) == "~/" then
    return (os.getenv("HOME") or "~") .. path:sub(2)
  end
  return path
end

--- A path with the home folder as `~` at its start, for a message: the
--- other way of `expand_path`.
function M.tilde(path: string): string
  local home = os.getenv("HOME")
  if home and path:sub(1, #home + 1) == home .. "/" then
    return "~" .. path:sub(#home + 1)
  end
  return path
end

local tmp_count = 0

--- The path of a new empty file in the temporary folder: `$TMPDIR`, or
--- `/tmp` when it is not set. Lua's `os.tmpname` always uses `/tmp`, which a
--- program that runs in a sandbox can not write. The caller removes the file.
function M.tmpname(): string
  local dir = os.getenv("TMPDIR") or "/tmp"
  local path: string
  repeat
    tmp_count = tmp_count + 1
    path = string.format("%s/paw-%d-%d-%d", dir, os.time(), math.floor(os.clock() * 1000000), tmp_count)
    local taken = io.open(path, "r")
    if taken then
      taken:close()
      path = nil
    end
  until path
  local made, err = io.open(path, "w")
  if not made then
    error("cannot make a temporary file in " .. dir .. ": " .. tostring(err), 2)
  end
  made:close()
  return path
end

-- The travel of a fader and a send: -60 to +6 dB. A level typed
-- (`grv`) can go past it, as far as the engine's own limits, -120 to
-- +24 dB.
M.FADER_MIN, M.FADER_MAX = -60, 6

--- The level a fader goes to from `now` when it is moved to `want`: in its
--- travel (`lo` to `hi`, the fader's when not given), but never back past
--- where it is. A part at +10 dB that is turned down goes to +9, not to
--- the top of the travel.
function M.fader_db(now: number, want: number, lo?: number, hi?: number): number
  lo, hi = lo or M.FADER_MIN, hi or M.FADER_MAX
  now = now or 0
  if want > now then
    return math.min(want, math.max(hi, now))
  end
  return math.max(want, math.min(lo, now))
end

--- `v` rounded to the nearest multiple of `step` (1).
function M.round(v: number, step?: number): number
  step = step or 1
  return math.floor(v / step + 0.5) * step
end

--- An amount with its word, in the plural unless it is 1:
--- `paw.util.amount(1, "beat")` is "1 beat", `paw.util.amount(0.5, "beat")`
--- is "0.5 beats".
function M.amount(n: number, word: string): string
  return string.format("%g %s%s", n, word, n == 1 and "" or "s")
end

--- A deep copy of a value: tables are copied all the way down (their
--- metatables are not), anything else is given back as it is.
function M.copy<T>(value: T): T
  if not (value is {Data: Data}) then
    return value
  end
  local out: {Data: Data} = {}
  for k, v in pairs(value as {Data: Data}) do
    out[k] = M.copy(v)
  end
  return out as T
end

--- Shallow copy with the fields of `extra` laid over it.
function M.merge<K, V>(base: {K: V}, extra: {K: V}): {K: V}
  local out: {K: V} = {}
  for k, v in pairs(base or {}) do
    out[k] = v
  end
  for k, v in pairs(extra or {}) do
    out[k] = v
  end
  return out
end

--- Cut or pad text to exactly `width` columns.
function M.fit(text: string | number, width: integer): string
  local str = tostring(text)
  local have = api.str_width(str)
  if have <= width then
    return str .. string.rep(" ", width - have)
  end
  local out, used = {}, 0
  for ch in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local w = api.str_width(ch)
    if used + w > width - 1 then
      break
    end
    out[#out + 1], used = ch, used + w
  end
  local ellipsis = paw.draw and paw.draw.g.ellipsis or "…"
  return table.concat(out) .. ellipsis .. string.rep(" ", width - used - 1)
end

--- The order of the entries that extensions add to a list of keys (the
--- pencil's keys, the insert kinds): by `order`, then by key.
function M.by_order(a: M.Ordered, b: M.Ordered): boolean
  if a.order ~= b.order then
    return a.order < b.order
  end
  return a.key < b.key
end

--- Break text into lines of at most `width` columns, at spaces. A word
--- wider than `width` gets a line of its own. Empty text gives one empty
--- line.
function M.wrap(text: string, width: integer): {string}
  local out: {string} = {}
  local line = ""
  for word in text:gmatch("%S+") do
    if line ~= "" and api.str_width(line .. " " .. word) > width then
      out[#out + 1], line = line, word
    else
      line = line == "" and word or line .. " " .. word
    end
  end
  out[#out + 1] = line
  return out
end

return M
