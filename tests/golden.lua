-- Tests of the golden screens (tests/tools/golden.lua): what a person sees
-- when a test has no golden screen yet.
-- Loaded by tests/suite.lua with its helpers.
local T = ...

T.test("a missing golden screen fails and gives the command that writes it", function()
  if os.getenv("PAW_BLESS") == "1" then return "PAW_BLESS=1 writes the missing file" end
  T.fresh()
  T.fails(
    function() T.expect_screen("never_blessed", 60, 16) end,
    'no golden screen tests/screens/golden/never_blessed.txt\n  to write it, run: PAW_BLESS=1 tests/tools/suite.sh only "a missing golden screen fails',
    "a screen with no file"
  )
end)
