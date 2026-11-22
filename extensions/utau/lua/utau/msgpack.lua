-- MessagePack for the engine protocol, in LuaJIT.
--
-- Lua numbers cannot tell an integer from a float or a float from a double,
-- and the engine's decoder is typed, so the writer has a function per wire
-- type. The reader returns plain Lua values: maps and arrays as tables, `bin`
-- as strings, and 64-bit integers too large for a double as decimal strings.
local ffi = require("ffi")

local M = {}
local char, byte, sub, concat = string.char, string.byte, string.sub, table.concat

local f32 = ffi.new("float[1]")
local f64 = ffi.new("double[1]")

local function be(n, v)
  local out = {}
  for i = n, 1, -1 do
    out[i] = char(v % 256)
    v = math.floor(v / 256)
  end
  return concat(out)
end

--- Little-endian unsigned, as the frame header uses.
function M.le32(v)
  return char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end

function M.read_le32(s, pos)
  local a, b, c, d = byte(s, pos, pos + 3)
  return a + b * 256 + c * 65536 + d * 16777216
end

-- Writer ------------------------------------------------------------------------

function M.null() return "\192" end

function M.bool(v) return v and "\195" or "\194" end

function M.uint(v)
  v = math.floor(v)
  if v < 128 then
    return char(v)
  elseif v < 256 then
    return "\204" .. char(v)
  elseif v < 65536 then
    return "\205" .. be(2, v)
  elseif v < 4294967296 then
    return "\206" .. be(4, v)
  end
  return "\207" .. be(8, v)
end

function M.int(v)
  v = math.floor(v)
  if v >= 0 then return M.uint(v) end
  if v >= -32 then
    return char(v + 256)
  elseif v >= -128 then
    return "\208" .. char(v + 256)
  elseif v >= -32768 then
    return "\209" .. be(2, v + 65536)
  elseif v >= -2147483648 then
    return "\210" .. be(4, v + 4294967296)
  end
  error("integer out of range: " .. v)
end

local function reversed(ptr, n)
  local s = ffi.string(ptr, n)
  return ffi.abi("le") and s:reverse() or s
end

function M.float(v)
  f32[0] = v
  return "\202" .. reversed(f32, 4)
end

function M.double(v)
  f64[0] = v
  return "\203" .. reversed(f64, 8)
end

function M.str(s)
  local n = #s
  if n < 32 then
    return char(160 + n) .. s
  elseif n < 256 then
    return "\217" .. char(n) .. s
  elseif n < 65536 then
    return "\218" .. be(2, n) .. s
  end
  return "\219" .. be(4, n) .. s
end

function M.bin(s)
  local n = #s
  if n < 256 then
    return "\196" .. char(n) .. s
  elseif n < 65536 then
    return "\197" .. be(2, n) .. s
  end
  return "\198" .. be(4, n) .. s
end

--- Header of an array of `n` items; the items follow.
function M.array(n)
  if n < 16 then
    return char(144 + n)
  elseif n < 65536 then
    return "\220" .. be(2, n)
  end
  return "\221" .. be(4, n)
end

function M.map(n)
  if n < 16 then
    return char(128 + n)
  elseif n < 65536 then
    return "\222" .. be(2, n)
  end
  return "\223" .. be(4, n)
end

--- An array whose items are written by `each(item)`.
function M.list(items, each)
  local out = { M.array(#items) }
  for i, item in ipairs(items) do
    out[i + 1] = each(item)
  end
  return concat(out)
end

--- An array of strings.
function M.strs(items) return M.list(items, M.str) end

-- Reader ------------------------------------------------------------------------

local function unsigned(s, pos, n)
  local v = 0
  for i = pos, pos + n - 1 do
    v = v * 256 + byte(s, i)
  end
  return v
end

local function uint64(s, pos)
  local v = 0ULL
  for i = pos, pos + 7 do
    v = v * 256 + byte(s, i)
  end
  if v < 9007199254740992ULL then return tonumber(v) end
  return (tostring(v):gsub("ULL$", ""))
end

local function signed(s, pos, n)
  local v = unsigned(s, pos, n)
  local half = 2 ^ (8 * n - 1)
  if v >= half then v = v - 2 * half end
  return v
end

local function float_at(s, pos, n)
  local ptr = n == 4 and f32 or f64
  local raw = sub(s, pos, pos + n - 1)
  if ffi.abi("le") then raw = raw:reverse() end
  ffi.copy(ptr, raw, n)
  return tonumber(ptr[0])
end

local decode

local function items(s, pos, n, map)
  local t = {}
  for i = 1, n do
    if map then
      local k
      k, pos = decode(s, pos)
      t[k], pos = decode(s, pos)
    else
      t[i], pos = decode(s, pos)
    end
  end
  return t, pos
end

--- Decode the value at `pos`; returns it and the position after it.
function decode(s, pos)
  local b = byte(s, pos)
  if not b then error("truncated msgpack") end
  if b < 128 then return b, pos + 1 end
  if b >= 224 then return b - 256, pos + 1 end
  if b < 144 then return items(s, pos + 1, b - 128, true) end
  if b < 160 then return items(s, pos + 1, b - 144, false) end
  if b < 192 then
    local n = b - 160
    return sub(s, pos + 1, pos + n), pos + 1 + n
  end
  if b == 192 then return nil, pos + 1 end
  if b == 194 then return false, pos + 1 end
  if b == 195 then return true, pos + 1 end
  if b == 196 or b == 217 then
    local n = byte(s, pos + 1)
    return sub(s, pos + 2, pos + 1 + n), pos + 2 + n
  end
  if b == 197 or b == 218 then
    local n = unsigned(s, pos + 1, 2)
    return sub(s, pos + 3, pos + 2 + n), pos + 3 + n
  end
  if b == 198 or b == 219 then
    local n = unsigned(s, pos + 1, 4)
    return sub(s, pos + 5, pos + 4 + n), pos + 5 + n
  end
  if b == 202 then return float_at(s, pos + 1, 4), pos + 5 end
  if b == 203 then return float_at(s, pos + 1, 8), pos + 9 end
  if b == 204 then return byte(s, pos + 1), pos + 2 end
  if b == 205 then return unsigned(s, pos + 1, 2), pos + 3 end
  if b == 206 then return unsigned(s, pos + 1, 4), pos + 5 end
  if b == 207 then return uint64(s, pos + 1), pos + 9 end
  if b == 208 then return signed(s, pos + 1, 1), pos + 2 end
  if b == 209 then return signed(s, pos + 1, 2), pos + 3 end
  if b == 210 then return signed(s, pos + 1, 4), pos + 5 end
  if b == 211 then return signed(s, pos + 1, 8), pos + 9 end
  if b == 220 then return items(s, pos + 3, unsigned(s, pos + 1, 2), false) end
  if b == 221 then return items(s, pos + 5, unsigned(s, pos + 1, 4), false) end
  if b == 222 then return items(s, pos + 3, unsigned(s, pos + 1, 2), true) end
  if b == 223 then return items(s, pos + 5, unsigned(s, pos + 1, 4), true) end
  error(string.format("unsupported msgpack type 0x%02x", b))
end

M.decode = decode

--- Little-endian 32-bit floats packed in a string, as a list of numbers.
--- (The engine and this machine are both little-endian x86-64 or ARM.)
function M.floats(s)
  local n = math.floor(#s / 4)
  local out = {}
  if n == 0 then return out end
  local buf = ffi.new("float[?]", n)
  ffi.copy(buf, s, n * 4)
  for i = 0, n - 1 do
    out[i + 1] = tonumber(buf[i])
  end
  return out
end

--- A hash or other 64-bit value as the decimal string used for keys.
function M.key(v)
  if type(v) == "number" then return string.format("%.0f", v) end
  return tostring(v)
end

return M
