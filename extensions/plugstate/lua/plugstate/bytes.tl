-- Bytes for state codecs: the bytes of a file, the binary numbers that
-- plugins write (32-bit and 64-bit floats, signed 32-bit and 64-bit
-- integers, little-endian as on the machines paw runs on), C arrays of
-- bytes for the loops over large states, and the FNV-1a hash. (Base64,
-- unsigned little-endian numbers and ZIP archives are the core's:
-- paw.bytes, paw.zip.)
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads. The parts of
-- LuaJIT's `ffi` and `bit` that plugstate uses have their types here, as
-- Teal's library does not name them.

--- A C array of numbers of LuaJIT's FFI, read and written by index from 0.
local record Cells
  metamethod __index: function(Cells, integer): number
  metamethod __newindex: function(Cells, integer, number)
end

--- A C array of bytes (or of other small integers) of LuaJIT's FFI.
local record Octets
  metamethod __index: function(Octets, integer): integer
  metamethod __newindex: function(Octets, integer, integer)
end

--- A 64-bit unsigned integer of LuaJIT's FFI: its arithmetic wraps at 64 bits.
local record U64
  metamethod __mul: function(U64, U64): U64
  metamethod __add: function(U64, number): U64
  metamethod __mod: function(U64, number): U64
end

--- LuaJIT's `ffi`, for arrays of numbers.
local record Ffi
  new: function(ctype: string, ...: number): Cells
  copy: function(target: Cells, source: string, size: integer)
  string: function(source: Cells, size: integer): string
end

--- LuaJIT's `ffi`, for arrays of bytes.
local record OctetFfi
  new: function(ctype: string, ...: integer): Octets
  copy: function(target: Octets, source: string, size: integer)
  string: function(source: Octets, size: integer): string
  cast: function(ctype: string, source: string): Octets
end

--- LuaJIT's `ffi`, for 64-bit integers.
local record U64Ffi
  new: function(ctype: string, init: number): U64
end

--- LuaJIT's `bit`, on 64-bit integers.
local record Bit
  bxor: function(a: U64, b: integer): U64
  tohex: function(a: U64): string
end

local ffi = (require as function(string): Ffi)("ffi")
local octet_ffi = ffi as OctetFfi
local u64_ffi = ffi as U64Ffi
local bit = (require as function(string): Bit)("bit")

local record M
  type Octets = Octets
  octets: function(ctype: string, ...: integer): Octets
  string: function(source: Octets, size: integer): string
  copy: function(target: Octets, source: string, size: integer)
end

--- The bytes of a file, or nil and why.
function M.read_file(path: string): string, string
  local f, err = io.open(path, "rb")
  if not f then
    return nil, err
  end
  local data = f:read("*a")
  f:close()
  return data
end

-- --- C arrays of bytes ------------------------------------------------------------

--- A new C array of `ctype` ("uint8_t[?]", "int8_t[256]"), with the size
--- or the value of each cell as LuaJIT's `ffi.new` takes them.
M.octets = octet_ffi.new

--- The first `size` bytes of a C array (`ffi.string`).
M.string = octet_ffi.string

--- Copy `size` bytes of a string into a C array (`ffi.copy`).
M.copy = octet_ffi.copy

--- The bytes of a string as a C array to read, without a copy.
function M.view(data: string): Octets
  return octet_ffi.cast("const uint8_t*", data)
end

-- --- numbers ----------------------------------------------------------------------

-- One cell of each kind, for the conversions.
local f1 = ffi.new("float[1]")
local d1 = ffi.new("double[1]")
local i1 = ffi.new("int32_t[1]")
local l1 = ffi.new("int64_t[1]")

--- The 32-bit float at `at` (from 1).
function M.f32(data: string, at: integer): number
  ffi.copy(f1, data:sub(at, at + 3), 4)
  return f1[0]
end

--- The four bytes of a 32-bit float.
function M.pack_f32(v: number): string
  f1[0] = v
  return ffi.string(f1, 4)
end

--- The 64-bit float at `at` (from 1).
function M.f64(data: string, at: integer): number
  ffi.copy(d1, data:sub(at, at + 7), 8)
  return d1[0]
end

--- The eight bytes of a 64-bit float.
function M.pack_f64(v: number): string
  d1[0] = v
  return ffi.string(d1, 8)
end

--- The signed 32-bit integer at `at` (from 1), or nil past the end.
function M.i32(data: string, at: integer): integer
  if at + 3 > #data then
    return nil
  end
  ffi.copy(i1, data:sub(at, at + 3), 4)
  return math.floor(i1[0])
end

--- The four bytes of a signed 32-bit integer.
function M.pack_i32(v: number): string
  i1[0] = v
  return ffi.string(i1, 4)
end

--- The signed 64-bit integer at `at` (from 1), as a Lua number.
function M.i64(data: string, at: integer): number
  ffi.copy(l1, data:sub(at, at + 7), 8)
  return tonumber(l1[0])
end

--- The eight bytes of a signed 64-bit integer.
function M.pack_i64(v: number): string
  l1[0] = v
  return ffi.string(l1, 8)
end

--- FNV-1a (64 bits) of bytes: its 16 hexadecimal digits, and the hash
--- modulo `modulo`.
function M.fnv1a64(data: string, modulo: integer): string, integer
  -- The start, 1469598103934665603 (as the plugin has it), is not exact as
  -- a double: it is made from its two halves of 32 bits. The prime is
  -- below 2^53, so it is exact.
  local h = u64_ffi.new("uint64_t", 342167472) * u64_ffi.new("uint64_t", 4294967296) + 1939669891
  local prime = u64_ffi.new("uint64_t", 1099511628211)
  local src = M.view(data)
  for i = 0, #data - 1 do
    h = bit.bxor(h, src[i]) * prime
  end
  return bit.tohex(h), math.floor(tonumber(h % modulo))
end

return M
