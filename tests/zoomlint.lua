-- The check of the time axis (tools/zoomlint.lua), with its allow-list
-- (tools/zoomlint-allowed.txt). Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq = T.test, T.eq
local zoomlint = dofile("tools/zoomlint.lua")

test(
  "zoomlint: no code turns beats into columns by its own `* zoom` or `/ zoom`",
  function() eq(table.concat(zoomlint.check("."), "\n"), "", "the problems") end
)

test("zoomlint: a new use fails, and a smaller count asks for a smaller line", function()
  local root = T.scratch .. "/zoomlint"
  os.execute("mkdir -p '" .. root .. "/runtime/lua/paw' '" .. root .. "/extensions/ext/lua' '" .. root .. "/tools'")
  T.write_file(root .. "/tools/zoomlint-allowed.txt", "# a comment\nextensions/ext/lua/old.lua 2 pixels\n")
  -- Two uses; none in a comment, none of the vertical zoom.
  T.write_file(
    root .. "/runtime/lua/paw/view.tl",
    "local x = (b - s) * paw.opt.zoom\n-- x / zoom\nlocal y = r * vzoom\nlocal b = x / (g.note_zoom)\n"
  )
  T.write_file(root .. "/extensions/ext/lua/old.lua", "local x = b * gui.zoom\n")
  T.write_file(root .. "/extensions/ext/tests.lua", "local x = b * zoom\n")
  T.write_file(root .. "/runtime/lua/paw/axis.tl", "local x = b * zoom\n")
  eq(
    table.concat(zoomlint.check(root), "\n"),
    table.concat({
      "runtime/lua/paw/view.tl:1: 2 uses of `* zoom` or `/ zoom`, 0 allowed. Put the beat on the time axis"
        .. " (paw.axis: x_of, beat_of, range, cells, beats) so that it takes the column that the ruler gives it",
      "tools/zoomlint-allowed.txt:2: 1 now: make the line `extensions/ext/lua/old.lua 1 ...`",
    }, "\n"),
    "the problems"
  )
end)
