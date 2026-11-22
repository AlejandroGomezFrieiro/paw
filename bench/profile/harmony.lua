-- How long paw takes to read all the chords and keys of a song: what the
-- kernel does when it opens it. After an edit, it reads again only what the
-- edit changed (paw/harmony/song.tl).
--   paw --clean --no-plugins -l bench/profile/harmony.lua <project dir> [rounds]
-- Prints one JSON line: the notes read, the chords found and the time of
-- each reading (median, min and max of the rounds, in ms), with a hash of
-- the chords so that two builds can be checked to read the same.
local paw = require("paw")
local api = paw.api
local dir, rounds = ...
assert(dir, "usage: harmony.lua <project dir> [rounds]")
rounds = tonumber(rounds) or 5
paw.open(dir)
paw.flush()
local harmony = paw.harmony
local song = require("paw.harmony.song")
local times, chords = {}, nil
for i = 1, rounds do
  -- Forget what was read: the reading is made again from all the notes.
  song.reset()
  harmony.invalidate()
  local t = api.now()
  chords = harmony.builtin(0, math.huge)
  times[i] = api.now() - t
end
table.sort(times)
local parts = {}
for _, c in ipairs(chords) do
  parts[#parts + 1] =
    string.format("%g:%g:%d:%s:%s", c.at, c.length, c.root, c.quality.name or tostring(c.quality), tostring(c.bass))
end
local text = table.concat(parts, " ")
local sum = 0
for i = 1, #text do
  sum = (sum * 31 + text:byte(i)) % 2147483647
end
print(
  string.format(
    '{"notes":%d,"chords":%d,"p50_ms":%.1f,"min_ms":%.1f,"max_ms":%.1f,"hash":%d}',
    #harmony.notes(),
    #chords,
    times[math.ceil(#times / 2)],
    times[1],
    times[#times],
    sum
  )
)
api.quit(0)
