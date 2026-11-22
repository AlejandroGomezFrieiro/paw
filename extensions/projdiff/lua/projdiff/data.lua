-- Plain data helpers for comparing and merging projects as decoded from
-- their files: tables of numbers, strings, booleans and tables. Nothing here
-- needs the kernel.
local M = {}

--- A number as short text that reads back as the same number: integers
--- without a point, other numbers with the fewest digits that are exact.
function M.num(n)
  if n ~= n then return "nan" end
  if n == math.huge then return "inf" end
  if n == -math.huge then return "-inf" end
  if n == math.floor(n) and math.abs(n) < 2 ^ 53 then return string.format("%d", n) end
  for digits = 15, 17 do
    local text = string.format("%." .. digits .. "g", n)
    if tonumber(text) == n then return text end
  end
  return string.format("%.17g", n)
end

--- A number to read: at most four decimals, so that what floating point
--- adds to a sum (0.8000000000000007) does not show.
function M.short(n)
  if type(n) ~= "number" or n ~= n or math.abs(n) == math.huge then return M.num(n) end
  local text = string.format("%.4f", n):gsub("0+$", ""):gsub("%.$", "")
  if text == "-0" then text = "0" end
  return text
end

--- Whether a table holds only the keys 1 to n (an empty one does).
function M.is_array(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n == #t
end

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end
M.sorted_keys = sorted_keys

local function quote(s)
  return '"' .. s:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
end

--- A value as JSON text with its keys in order: the same value is always the
--- same text, so that it can stand for the value in comparisons and sets.
function M.canon(v)
  local kind = type(v)
  if kind == "number" then return M.num(v) end
  if kind == "string" then return quote(v) end
  if kind ~= "table" then return tostring(v) end
  local out = {}
  if M.is_array(v) then
    for i = 1, #v do
      out[i] = M.canon(v[i])
    end
    return "[" .. table.concat(out, ",") .. "]"
  end
  for _, k in ipairs(sorted_keys(v)) do
    out[#out + 1] = quote(tostring(k)) .. ":" .. M.canon(v[k])
  end
  return "{" .. table.concat(out, ",") .. "}"
end

--- Whether two values are the same data.
function M.equal(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do
    if not M.equal(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

--- A value for a line of text: strings quoted, long values cut; with
--- `short` a number as `M.short` writes it.
function M.show(v, limit, short)
  limit = limit or 48
  if short and type(v) == "number" then return M.short(v) end
  local text
  if v == nil then
    text = "none"
  elseif type(v) == "string" then
    text = quote(v)
  elseif type(v) == "table" then
    text = M.canon(v)
  elseif type(v) == "number" then
    text = M.num(v)
  else
    text = tostring(v)
  end
  if #text > limit then text = text:sub(1, limit - 1) .. "…" end
  return text
end

local NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

--- A MIDI note number as its name: 60 is C4.
function M.pitch(n)
  if type(n) ~= "number" then return tostring(n) end
  return NAMES[n % 12 + 1] .. (math.floor(n / 12) - 1)
end

--- A list of objects by one of their fields: `{ by = { [key] = item }, order = { key... } }`.
function M.by(list, field)
  local by, order = {}, {}
  for _, item in ipairs(list or {}) do
    local key = item[field]
    if by[key] == nil then order[#order + 1] = key end
    by[key] = item
  end
  return { by = by, order = order }
end

-- What names the items of a list: `id`, or what a send, a tempo change, a
-- slot or a warp marker is named by; the points of a lane are pairs, named
-- by their beat (field 1).
local KEYS = { "id", "target", "beat", "row", "source", 1 }

--- The field that names the items of the lists given, if every item has one.
function M.key_field(...)
  local any
  for i = 1, select("#", ...) do
    local list = select(i, ...)
    if type(list) == "table" then
      for _, item in ipairs(list) do
        if type(item) ~= "table" then return nil end
        any = true
      end
    end
  end
  if not any then return nil end
  for _, field in ipairs(KEYS) do
    local all = true
    for i = 1, select("#", ...) do
      local list = select(i, ...)
      if type(list) == "table" then
        for _, item in ipairs(list) do
          if type(item) ~= "table" or type(item[field]) ~= "number" then
            all = false
            break
          end
        end
      end
      if not all then break end
    end
    if all then return field end
  end
  return nil
end

return M
