-- Tests of ranges on the command line: `:'<,'>` for the last selection and
-- `:5,8` for bars, given to commands as `ctx.range`. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local test, eq, fails, keys = T.test, T.eq, T.fails, T.keys

local got
paw.command(
  "test.range",
  function(ctx) got = { range = ctx.range, selection = paw.keymap.selection(), args = ctx.args } end,
  { range = true, desc = "Remember the range it was given" }
)
paw.command(
  "test.norange",
  function(ctx) got = { range = ctx.range, selection = paw.keymap.selection() } end,
  { desc = "Remember the selection it saw" }
)

test("ranges: : in visual mode starts the prompt with '<,'>, and the command gets the selection", function()
  T.three_clips()
  got = nil
  keys("vl:")
  eq(require("paw.views.cmdline").state().before, "'<,'>", "the prompt starts with the range")
  eq(paw.keymap.mode, "c", "typing a command")
  keys("test.norange<CR>")
  eq(got.range.selection, true, "the command is told it has the selection")
  eq(got.selection and got.selection.view, "arrange", "and keymap.selection() returns it while it runs")
  eq(got.selection.c0, 0, "from where it began")
  eq(got.selection.c1 > got.selection.c0, true, "to the cursor")
  eq(paw.keymap.selection(), nil, "afterwards visual mode is over")
  got = nil
  paw.commands.exec("'<,'>test.norange")
  eq(got.selection.c0, 0, "'<,'> typed later names the last selection again")
end)

test("ranges: a range of bars goes to commands that take one, and nowhere else", function()
  T.three_clips()
  got = nil
  paw.commands.exec("2,3test.range a")
  eq(got.range.bars[1] .. "," .. got.range.bars[2], "2,3", "the bars")
  eq(got.range.from, paw.time.bar_start(2), "from the start of bar 2")
  eq(got.range.to, paw.time.bar_start(4), "to the end of bar 3")
  eq(got.args[1], "a", "the arguments after the name")
  paw.commands.exec("5 test.range")
  eq(got.range.bars[1] .. "," .. got.range.bars[2], "5,5", "one bar")
  fails(function() paw.commands.exec("2,3test.norange") end, "takes no range of bars")
  fails(function() paw.commands.exec("3,2test.range") end, "from the first to the last")
  paw.commands.exec("test.range")
  eq(got.range, nil, "no range, none given")
end)

test("ranges: completion keeps the range in front and completes what follows", function()
  T.three_clips()
  local found
  for _, c in ipairs(paw.commands.complete("5,8test.ran")) do
    if c.text == "5,8test.range" then found = true end
  end
  eq(found, true, "5,8test.ran completes to 5,8test.range")
end)
