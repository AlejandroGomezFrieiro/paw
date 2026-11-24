-- The check of the grid of time: no code of the runtime or of an extension
-- does grid arithmetic of its own. It does not read `opt.grid` or
-- `opt.note_grid`, round to a grid (`util.round(x, grid)`) or divide by
-- one (`/ grid`). The grid module (runtime/lua/paw/timegrid.tl) does that,
-- with lines that start again at each bar and follow the meter, the swing,
-- the folds and the scope, in whole ticks. The options
-- (runtime/lua/paw/options.tl) and the status line, which shows the
-- setting, read the options too. Code that needs a step in beats calls
-- `paw.timegrid.step()`. It reads text only, so plain LuaJIT runs it (the
-- flake's `zoomlint` check), and so does paw (the suite's tests/gridlint.lua).
--
--   luajit tools/gridlint.lua          check the code against the allow-list
--   luajit tools/gridlint.lua counts   print the uses of today, in the format of the allow-list
--
-- tools/gridlint-allowed.txt holds one line `<file> <count> <reason>` for
-- each file that keeps such a use with a reason. It works as the list of
-- tools/zoomlint.lua: a count that goes up fails, and a count that goes
-- down fails until its line is made smaller.
local zoomlint = dofile("tools/zoomlint.lua")

local M = {}

M.ALLOWED = "tools/gridlint-allowed.txt"
-- The files that own the grid setting: the grid module, the options and
-- the status line.
M.OWN = { "runtime/lua/paw/timegrid.tl", "runtime/lua/paw/options.tl", "runtime/lua/paw/statusline.tl" }

--- The uses of grid arithmetic in a text: the line of each. `opt.grid` and
--- `opt.note_grid` (`paw.opt.grid` too), `util.round(...)` with a name that
--- ends in `grid` in its arguments, and `/` before such a name (`/ grid`,
--- `/ s.grid`, `/ (note_grid)`). `paw.timegrid` is the module, not a grid.
--- What follows `--` on a line is a comment, and is left out.
function M.uses(text)
  local out = {}
  local n = 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local code = line:gsub("%-%-.*$", "")
    for _ in code:gmatch("opt%.grid%f[^%w_]") do
      out[#out + 1] = n
    end
    for _ in code:gmatch("opt%.note_grid%f[^%w_]") do
      out[#out + 1] = n
    end
    for args in code:gmatch("util%.round(%b())") do
      if args:match("[%w_]*grid%f[^%w_%.]") then out[#out + 1] = n end
    end
    for _ in code:gmatch("/%s*%(?%s*[%w_%.]-grid%f[^%w_%.]") do
      out[#out + 1] = n
    end
  end
  return out
end

local GRID = {
  allowed = M.ALLOWED,
  own = M.OWN,
  uses = M.uses,
  what = "grid arithmetic (`opt.grid`, `opt.note_grid`, `util.round(.., grid)`, `/ grid`)",
  fix = "Ask the grid of time (paw.timegrid: window, next, prev, floor, nearest, steps, step) so that"
    .. " the move stops on the lines that the grid draws",
}

--- The problems under `root`: each a line of text. Empty when all is well.
function M.check(root) return zoomlint.scan(root, GRID) end

--- The uses of today, as lines of the allow-list (with no reason).
function M.counts(root) return zoomlint.scan_counts(root, GRID) end

-- Run as a script (`luajit tools/gridlint.lua`), not loaded by a test.
if arg and arg[0] and arg[0]:match("gridlint%.lua$") and not paw then
  if arg[1] == "counts" then
    print(table.concat(M.counts("."), "\n"))
    os.exit(0)
  end
  local problems = M.check(".")
  if #problems > 0 then
    io.stderr:write(table.concat(problems, "\n") .. "\n")
    os.exit(1)
  end
  print("gridlint: the grid of time is in one module")
end

return M
