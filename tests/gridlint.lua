-- The check of the grid of time (tools/gridlint.lua), with its allow-list
-- (tools/gridlint-allowed.txt). Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq = T.test, T.eq
local gridlint = dofile("tools/gridlint.lua")

test(
  "gridlint: no code does grid arithmetic of its own outside the grid of time",
  function() eq(table.concat(gridlint.check("."), "\n"), "", "the problems") end
)

test("gridlint: each kind of grid arithmetic counts, outside the files that own the grid", function()
  local root = T.scratch .. "/gridlint"
  os.execute("mkdir -p '" .. root .. "/runtime/lua/paw' '" .. root .. "/extensions/ext/lua' '" .. root .. "/tools'")
  T.write_file(root .. "/tools/gridlint-allowed.txt", "# a comment\nextensions/ext/lua/old.lua 2 its own grid\n")
  -- Four uses; none in a comment, none of the module paw.timegrid.
  T.write_file(
    root .. "/runtime/lua/paw/view.tl",
    table.concat({
      "local step = paw.opt.grid",
      "local b = util.round(beat, s.grid)",
      "local n = x / (note_grid) -- x / grid",
      "local y = options.opt.note_grid",
      "local z = x / paw.timegrid.step()",
    }, "\n")
  )
  T.write_file(root .. "/extensions/ext/lua/old.lua", "local k = beat / grid\n")
  T.write_file(root .. "/extensions/ext/tests.lua", "local k = beat / grid\n")
  T.write_file(root .. "/runtime/lua/paw/timegrid.tl", "local k = beat / grid\n")
  eq(
    table.concat(gridlint.check(root), "\n"),
    table.concat({
      "runtime/lua/paw/view.tl:1: 4 uses of grid arithmetic (`opt.grid`, `opt.note_grid`, `util.round(.., grid)`,"
        .. " `/ grid`), 0 allowed. Ask the grid of time (paw.timegrid: window, next, prev, floor, nearest, steps,"
        .. " step) so that the move stops on the lines that the grid draws",
      "tools/gridlint-allowed.txt:2: 1 now: make the line `extensions/ext/lua/old.lua 1 ...`",
    }, "\n"),
    "the problems"
  )
end)
