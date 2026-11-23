-- The check of the word part (tools/partlint.lua), with its allow-list
-- (tools/partlint-allowed.txt). Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq = T.test, T.eq
local partlint = dofile("tools/partlint.lua")

test(
  'partlint: no name, message or page calls the container a "track"',
  function() eq(table.concat(partlint.check("."), "\n"), "", "the problems") end
)

test("partlint: the word counts in any case and inside names, and its other senses do not", function()
  local text = table.concat({
    "local t = paw.add_track() -- a Track",
    "let id: TrackId = TRACK_ID;",
    "#[track_caller] a pitch tracker, tracking, untracked, heaptrack, keytrack",
  }, "\n")
  eq(table.concat(partlint.uses(text), " "), "1 1 2 2", "the lines of the uses")
end)
