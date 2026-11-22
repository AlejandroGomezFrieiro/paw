-- One short run of the fuzzer (bench/fuzz.lua): random edits, undo, save
-- and load, renders, with every invariant it checks.
local T = ...
local test, eq = T.test, T.eq

test("a short run of the fuzzer keeps every invariant: undo, save then load, renders", function()
  local dir = T.scratch .. "/fuzz"
  os.execute("mkdir -p '" .. dir .. "'")
  local env = string.format(
    "BENCH_TMP='%s' XDG_DATA_HOME='%s' XDG_STATE_HOME='%s' XDG_CACHE_HOME='%s' XDG_CONFIG_HOME='%s'",
    dir,
    dir,
    dir,
    dir,
    dir
  )
  local pipe = io.popen(env .. " /proc/self/exe --clean --no-plugins --audio null -l bench/fuzz.lua 1 120 2>&1")
  local out = pipe:read("*a")
  local ok = pipe:close()
  eq(ok == true and out:find('"failed"', 1, true) == nil, true, "the fuzzer's seed 1: " .. out:sub(-1500))
end)
