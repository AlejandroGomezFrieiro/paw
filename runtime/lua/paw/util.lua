-- Small helpers with no dependencies on the rest of the runtime.
local M = {}

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then return a < b end
    return tostring(a) < tostring(b)
  end)
  return keys
end

--- Render any value as readable Lua-like text.
function M.inspect(value, indent, seen)
  indent, seen = indent or "", seen or {}
  if type(value) == "string" then return string.format("%q", value) end
  if type(value) ~= "table" then return tostring(value) end
  if seen[value] then return "<cycle>" end
  seen[value] = true
  if next(value) == nil then return "{}" end
  local parts, inner = {}, indent .. "  "
  local n = #value
  for i = 1, n do parts[#parts + 1] = inner .. M.inspect(value[i], inner, seen) end
  for _, k in ipairs(sorted_keys(value)) do
    if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then
      local key = type(k) == "string" and k:match("^[%a_][%w_]*$") and k or "[" .. M.inspect(k) .. "]"
      parts[#parts + 1] = inner .. key .. " = " .. M.inspect(value[k], inner, seen)
    end
  end
  seen[value] = nil
  return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

--- `v`, kept between `lo` and `hi`.
function M.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

--- A path as typed, with `~` at its start for the home folder, as a shell
--- reads it: `~/mix.wav`. Every command that takes a file name reads it so.
function M.expand_path(path)
  if type(path) ~= "string" then return path end
  if path == "~" or path:sub(1, 2) == "~/" then return (os.getenv("HOME") or "~") .. path:sub(2) end
  return path
end

-- The travel of a fader and a send: -60 to +6 dB. A level typed
-- (`grv`) can go past it, as far as the engine's own limits, -120 to
-- +24 dB.
M.FADER_MIN, M.FADER_MAX = -60, 6

--- The level a fader goes to from `now` when it is moved to `want`: in its
--- travel (`lo` to `hi`, the fader's when not given), but never back past
--- where it is. A track at +10 dB that is turned down goes to +9, not to
--- the top of the travel.
function M.fader_db(now, want, lo, hi)
  lo, hi = lo or M.FADER_MIN, hi or M.FADER_MAX
  now = now or 0
  if want > now then return math.min(want, math.max(hi, now)) end
  return math.max(want, math.min(lo, now))
end

--- `v` rounded to the nearest multiple of `step` (1).
function M.round(v, step)
  step = step or 1
  return math.floor(v / step + 0.5) * step
end

--- A deep copy of a value: tables are copied all the way down (their
--- metatables are not), anything else is given back as it is.
function M.copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = M.copy(v) end
  return out
end

--- Shallow copy with the fields of `extra` laid over it.
function M.merge(base, extra)
  local out = {}
  for k, v in pairs(base or {}) do out[k] = v end
  for k, v in pairs(extra or {}) do out[k] = v end
  return out
end

--- Cut or pad text to exactly `width` columns.
function M.fit(text, width)
  text = tostring(text)
  local have = paw.api.str_width(text)
  if have <= width then return text .. string.rep(" ", width - have) end
  local out, used = {}, 0
  for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local w = paw.api.str_width(ch)
    if used + w > width - 1 then break end
    out[#out + 1], used = ch, used + w
  end
  return table.concat(out) .. (paw.draw and paw.draw.g.ellipsis or "…") .. string.rep(" ", width - used - 1)
end

return M
