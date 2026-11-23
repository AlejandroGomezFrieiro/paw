-- The globals of LuaJIT on PUC Lua 5.2, which paw runs on where LuaJIT
-- cannot run: in a BrowserPod pod (web/browserpod/README.md). The kernel
-- runs this file before everything else, in place of a module, so it is
-- Lua and not Teal: it defines globals, which Teal does not allow.
-- paw.compat then adds the Lua 5.3 library, as with LuaJIT.
-- luacheck: globals loadstring unpack setfenv getfenv bit, read globals bit32
-- It sets and reads fields that Lua 5.2 or LuaJIT lacks (math.pow, package.searchers).
-- luacheck: ignore 122 142 143
if jit then return end
loadstring = loadstring or load
unpack = unpack or table.unpack
table.unpack = table.unpack or unpack
table.maxn = table.maxn
  or function(t)
    local n = 0
    for k in pairs(t) do
      if type(k) == "number" and k > n then n = k end
    end
    return n
  end
math.log10 = math.log10 or function(x) return math.log(x, 10) end
math.pow = math.pow or function(a, b) return a ^ b end
math.mod = math.mod or math.fmod
package.loaders = package.loaders or package.searchers
-- LuaJIT's `table.new(narray, nhash)` makes a table with room for its items.
-- Lua 5.2 has no such function: the table is empty and grows when it fills.
package.preload["table.new"] = package.preload["table.new"] or function()
  return function() return {} end
end

if not setfenv then
  -- The upvalue `_ENV` of a function, as its environment.
  local function findenv(f)
    local i = 1
    while true do
      local name, value = debug.getupvalue(f, i)
      if name == "_ENV" then return i, value end
      if not name then return nil end
      i = i + 1
    end
  end
  getfenv = function(f)
    f = type(f) == "function" and f or debug.getinfo((f or 1) + 1, "f").func
    local _, env = findenv(f)
    return env or _G
  end
  setfenv = function(f, env)
    f = type(f) == "function" and f or debug.getinfo((f or 1) + 1, "f").func
    local i = findenv(f)
    if i then debug.upvaluejoin(f, i, function() return env end, 1) end
    return f
  end
end

-- LuaJIT's `bit` on Lua 5.2's `bit32`: the results are signed 32-bit
-- numbers, as LuaJIT gives them.
if not bit and bit32 then
  local function s(x)
    x = x % 4294967296
    if x >= 2147483648 then x = x - 4294967296 end
    return x
  end
  bit = {
    band = function(...) return s(bit32.band(...)) end,
    bor = function(...) return s(bit32.bor(...)) end,
    bxor = function(...) return s(bit32.bxor(...)) end,
    bnot = function(x) return s(bit32.bnot(x)) end,
    lshift = function(x, n) return s(bit32.lshift(x, n)) end,
    rshift = function(x, n) return s(bit32.rshift(x, n)) end,
    arshift = function(x, n) return s(bit32.arshift(x, n)) end,
    tobit = s,
  }
end
