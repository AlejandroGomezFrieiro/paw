-- The Lua 5.3 standard library on LuaJIT, which Teal's checker declares and
-- its compiled code calls: `math.type` for `x is integer`,
-- `math.tointeger`, `table.unpack`, `table.move`, `utf8`, and `bit32` for
-- the operators `& | ~ << >>`. The kernel loads this module first, before
-- the runtime and before any extension, so Teal's code and Lua's code see
-- one library.
--
-- Most of it is lua-compat-5.3 (runtime/lua/compat53, release 0.14.4,
-- unchanged), in the mode that changes the globals. Its C parts are not in
-- the program. A C function stops the trace that LuaJIT compiles, and two of
-- them have a Lua form here that LuaJIT compiles: `bit32` on LuaJIT's own
-- `bit`, and `utf8` (as Lua 5.3's lutf8lib.c does it). `string.pack` and
-- the C forms of `table` and `io` are not here: compat-5.3 has Lua forms of
-- `table` and `io`, and `ffi` packs bytes.
--
-- compat-5.3 also puts a Lua function in front of `string.find`,
-- `string.match`, `string.gsub` and `string.gmatch`, so that a pattern can
-- hold a zero byte. That made a search for plain text 250 times slower,
-- because LuaJIT no longer compiled it, and a match two times slower. This
-- module gives back LuaJIT's own four functions: write `%z` for a zero byte
-- in a pattern, as Lua 5.1 does. It gives back LuaJIT's own `ipairs` too: the
-- one of compat-5.3 follows `__index` and keeps short loops out of the traces.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua. It uses no
-- bitwise operator and no `is integer`, which need what it makes.

local record Bit
  band: function(...: number): number
  bor: function(...: number): number
  bxor: function(...: number): number
  bnot: function(number): number
  lshift: function(number, number): number
  rshift: function(number, number): number
  arshift: function(number, number): number
  rol: function(number, number): number
  ror: function(number, number): number
end

--- Lua 5.2's bit32: each result is an integer from 0 to 2^32 - 1.
local record Bit32
  band: function(...: number): integer
  bor: function(...: number): integer
  bxor: function(...: number): integer
  btest: function(...: number): boolean
  bnot: function(number): integer
  lshift: function(number, number): integer
  rshift: function(number, number): integer
  arshift: function(number, number): integer
  lrotate: function(number, number): integer
  rrotate: function(number, number): integer
  extract: function(number, number, ?number): integer
  replace: function(number, number, number, ?number): integer
end

local record Utf8
  char: function(...: number): string
  charpattern: string
  codepoint: function(string, ?number, ?number): integer...
  codes: function(string): (function(string, integer): (integer, integer), string, integer)
  len: function(string, ?number, ?number): integer, integer
  offset: function(string, number, ?number): integer
end

local record Globals
  bit: Bit
  bit32: Bit32
  require: function(string)
  unpack: function({integer}): integer...
end
local G = _G as Globals
local bit = G.bit

local floor = math.floor
local byte, char, format = string.byte, string.char, string.format

-- An error in the caller of the function that calls this one, or `level`
-- functions further out.
local function argerror(n: integer, name: string, message: string, level?: integer)
  error(format("bad argument #%d to '%s' (%s)", n, name, message), level or 3)
end

local function integer(x: number, n: integer, name: string): integer
  local i = tonumber(x)
  if not i or i % 1 ~= 0 then
    argerror(n, name, i and "number has no integer representation" or "number expected", 4)
  end
  return floor(i)
end

------------------------------------------------------------------------
-- bit32

local U = 4294967296 -- 2^32

local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local lsh, rsh, arsh = bit.lshift, bit.rshift, bit.arshift

local bit32: Bit32 = {}

function bit32.band(...: number): integer
  return floor(band(-1, ...) % U)
end

function bit32.bor(...: number): integer
  return floor(bor(0, ...) % U)
end

function bit32.bxor(...: number): integer
  return floor(bxor(0, ...) % U)
end

function bit32.btest(...: number): boolean
  return band(-1, ...) ~= 0
end

function bit32.bnot(x: number): integer
  return floor(bnot(x) % U)
end

function bit32.lshift(x: number, disp: number): integer
  if disp < 0 then
    return bit32.rshift(x, -disp)
  end
  if disp >= 32 then
    return 0
  end
  return floor(lsh(x, disp) % U)
end

function bit32.rshift(x: number, disp: number): integer
  if disp < 0 then
    return bit32.lshift(x, -disp)
  end
  if disp >= 32 then
    return 0
  end
  return floor(rsh(x, disp) % U)
end

function bit32.arshift(x: number, disp: number): integer
  if disp < 0 then
    return bit32.lshift(x, -disp)
  end
  if disp >= 32 then
    disp = 31
  end
  return floor(arsh(x, disp) % U)
end

function bit32.lrotate(x: number, disp: number): integer
  return floor(bit.rol(x, disp % 32) % U)
end

function bit32.rrotate(x: number, disp: number): integer
  return floor(bit.ror(x, disp % 32) % U)
end

local function field(name: string, f: number, w: number): integer, integer
  local fi, wi = integer(f, 2, name), integer(w or 1, 3, name)
  if fi < 0 then
    argerror(2, name, "field cannot be negative", 4)
  end
  if wi <= 0 then
    argerror(3, name, "width must be positive", 4)
  end
  if fi + wi > 32 then
    error("trying to access non-existent bits", 3)
  end
  return fi, wi
end

function bit32.extract(n: number, f: number, w?: number): integer
  local fi, wi = field("extract", f, w)
  return floor(band(rsh(n, fi), rsh(-1, 32 - wi)) % U)
end

function bit32.replace(n: number, v: number, f: number, w?: number): integer
  local fi, wi = field("replace", f, w)
  local mask = rsh(-1, 32 - wi)
  return floor(bor(band(n, bnot(lsh(mask, fi))), lsh(band(v, mask), fi)) % U)
end

------------------------------------------------------------------------
-- utf8, as Lua 5.3's lutf8lib.c

local MAXUTF = 0x10FFFF
local LIMITS = {0x7F, 0x7FF, 0xFFFF}

local function iscont(s: string, i: integer): boolean
  local b = byte(s, i)
  return b ~= nil and b >= 0x80 and b < 0xC0
end

-- The code point at byte `i` and the byte after it, or nil.
local function decode(s: string, i: integer): integer, integer
  local c = byte(s, i)
  if not c then
    return nil
  end
  if c < 0x80 then
    return c, i + 1
  end
  local count, res: integer, integer
  if c < 0xC0 then
    return nil
  elseif c < 0xE0 then
    count, res = 1, c - 0xC0
  elseif c < 0xF0 then
    count, res = 2, c - 0xE0
  elseif c < 0xF8 then
    count, res = 3, c - 0xF0
  else
    return nil
  end
  for k = 1, count do
    local cc = byte(s, i + k)
    if not cc or cc < 0x80 or cc >= 0xC0 then
      return nil
    end
    res = res * 64 + (cc - 0x80)
  end
  if res > MAXUTF or res <= LIMITS[count] then
    return nil
  end
  return res, i + count + 1
end

-- A position from the end of the string when it is negative.
local function posrelat(pos: integer, len: integer): integer
  if pos >= 0 then
    return pos
  end
  if -pos > len then
    return 0
  end
  return len + pos + 1
end

local utf: Utf8 = {charpattern = "[%z\1-\127\194-\244][\128-\191]*"}

local function encode(code: integer): string
  if code < 0x80 then
    return char(code)
  end
  if code < 0x800 then
    return char(0xC0 + floor(code / 0x40), 0x80 + code % 0x40)
  end
  if code < 0x10000 then
    return char(0xE0 + floor(code / 0x1000), 0x80 + floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
  end
  return char(
    0xF0 + floor(code / 0x40000),
    0x80 + floor(code / 0x1000) % 0x40,
    0x80 + floor(code / 0x40) % 0x40,
    0x80 + code % 0x40
  )
end

function utf.char(...: number): string
  local n = select("#", ...)
  local parts: {string} = {}
  for i = 1, n do
    local code = integer((select(i, ...)), i, "utf8.char")
    if code < 0 or code > MAXUTF then
      argerror(i, "utf8.char", "value out of range")
    end
    parts[i] = encode(code)
  end
  return table.concat(parts)
end

function utf.codepoint(s: string, i?: number, j?: number): integer...
  local len = #s
  local posi = posrelat(integer(i or 1, 2, "utf8.codepoint"), len)
  local pose = posrelat(integer(j or posi, 3, "utf8.codepoint"), len)
  if posi < 1 then
    argerror(2, "utf8.codepoint", "out of range")
  end
  if pose > len then
    argerror(3, "utf8.codepoint", "out of range")
  end
  if posi > pose then
    return
  end
  local codes: {integer} = {}
  local p = posi
  while p <= pose do
    local code, nextp = decode(s, p)
    if not code then
      error("invalid UTF-8 code", 2)
    end
    codes[#codes + 1] = code
    p = nextp
  end
  return G.unpack(codes)
end

function utf.len(s: string, i?: number, j?: number): integer, integer
  local len = #s
  local posi = posrelat(integer(i or 1, 2, "utf8.len"), len)
  local posj = posrelat(integer(j or -1, 3, "utf8.len"), len)
  if posi < 1 or posi - 1 > len then
    argerror(2, "utf8.len", "initial position out of string")
  end
  if posj > len then
    argerror(3, "utf8.len", "final position out of string")
  end
  local n = 0
  while posi <= posj do
    local _, nextp = decode(s, posi)
    if not nextp then
      return nil, posi
    end
    posi = nextp
    n = n + 1
  end
  return n
end

function utf.offset(s: string, n: number, i?: number): integer
  local len = #s
  local ni = integer(n, 2, "utf8.offset")
  local posi = posrelat(integer(i or (ni >= 0 and 1 or len + 1), 3, "utf8.offset"), len)
  if posi < 1 or posi - 1 > len then
    argerror(3, "utf8.offset", "position out of range")
  end
  posi = posi - 1 -- from 0, as in C
  if ni == 0 then
    while posi > 0 and iscont(s, posi + 1) do
      posi = posi - 1
    end
    return posi + 1
  end
  if iscont(s, posi + 1) then
    error("initial position is a continuation byte", 2)
  end
  if ni < 0 then
    while ni < 0 and posi > 0 do
      repeat
        posi = posi - 1
      until not (posi > 0 and iscont(s, posi + 1))
      ni = ni + 1
    end
  else
    ni = ni - 1
    while ni > 0 and posi < len do
      repeat
        posi = posi + 1
      until not iscont(s, posi + 1)
      ni = ni - 1
    end
  end
  if ni == 0 then
    return posi + 1
  end
  return nil
end

local function codes_next(s: string, i: integer): integer, integer
  local len = #s
  local n = i - 1
  if n < 0 then
    n = 0
  elseif n < len then
    n = n + 1
    while iscont(s, n + 1) do
      n = n + 1
    end
  end
  if n >= len then
    return nil
  end
  local code, nextp = decode(s, n + 1)
  if not code or iscont(s, nextp) then
    error("invalid UTF-8 code", 2)
  end
  return n + 1, code
end

function utf.codes(s: string): (function(string, integer): (integer, integer), string, integer)
  return codes_next, s, 0
end

------------------------------------------------------------------------
-- Load compat-5.3.

local preload = package.preload
preload["compat53.utf8"] = function(): Utf8 return utf end
-- compat-5.3 looks for its C parts and for `struct`: say that they are not
-- here, so it does not find a copy that is on the system.
local absent = {"compat53.table", "compat53.io", "compat53.string", "struct"}
for _, name in ipairs(absent) do
  preload[name] = function(): Utf8 error("not in paw", 0) end
end

local libs = _G as {string: {string: function}}
local own: {string: function} = {}
local patterns = {"find", "match", "gsub", "gmatch"}
for _, name in ipairs(patterns) do
  own[name] = libs.string[name]
end
local globals = _G as {string: function}
local builtin_ipairs = globals.ipairs
G.require("compat53")
-- compat-5.3 puts a Lua ipairs in front of the built-in one, so that
-- ipairs follows `__index` (Lua 5.3). LuaJIT compiles its own ipairs into a
-- trace, and a Lua function breaks short loops. No paw code walks a proxy
-- table with ipairs, so the built-in comes back.
globals.ipairs = builtin_ipairs
for _, name in ipairs(absent) do
  preload[name] = nil
end
preload["compat53.utf8"] = nil

local module = package.loaded["compat53.module"] as {string: {string: function}}
for _, name in ipairs(patterns) do
  libs.string[name] = own[name]
  module.string[name] = own[name]
end

G.bit32 = bit32
package.loaded.bit32 = bit32

return {bit32 = bit32, utf8 = utf}
