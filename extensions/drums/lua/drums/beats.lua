-- Beats to start from: a bar of sixteenth notes for each piece, by General
-- MIDI note. `x` is a hit, `X` an accent, `o` a ghost note, `.` nothing.
-- Add your own the same way:
--
--   require("drums.beats").list.shuffle = { label = "Shuffle", rows = { [36] = "x.....x.x.......", ... } }
local util = paw.util
local M = {}

local VELOCITY = { x = 100, X = 124, o = 52 }

M.list = {
  rock = {
    label = "Rock: kick on one and three, snare on two and four, eighth-note hats",
    rows = {
      [42] = "x.x.x.x.x.x.x.x.",
      [38] = "....X.......X...",
      [36] = "x.......x.x.....",
    },
  },
  house = {
    label = "House: four on the floor, open hats between",
    rows = {
      [42] = "x.x.x.x.x.x.x.x.",
      [46] = "..x...x...x...x.",
      [39] = "....x.......x...",
      [36] = "X...x...X...x...",
    },
  },
  boombap = {
    label = "Boom bap: a lazy kick, a hard snare, ghost notes",
    rows = {
      [42] = "x.x.x.x.x.x.x.xo",
      [38] = "....X..o....X...",
      [36] = "x.......xx....x.",
    },
  },
  funk = {
    label = "Funk: sixteenth hats, syncopated kick, ghosted snare",
    rows = {
      [42] = "XxxxXxxxXxxxXxxx",
      [38] = "....X..o.o..X..o",
      [36] = "x..x..x...x..x..",
    },
  },
  halftime = {
    label = "Half time: the snare on three, ride on the beat",
    rows = {
      [51] = "x...x...x...x...",
      [42] = "..x...x...x...x.",
      [38] = "........X.......",
      [36] = "x.....x...x.....",
    },
  },
  trap = {
    label = "Trap: rolling hats, a clap on three",
    rows = {
      [42] = "x.x.x.xxx.x.xxxx",
      [39] = "........X.......",
      [36] = "X......x..x.....",
    },
  },
}

--- The names of the beats, sorted.
function M.names()
  local out = {}
  for name in pairs(M.list) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

--- Fill a clip with a beat, a bar at a time to its end, in place of what it
--- had. One edit. Returns the hits written, and how many of the notes that
--- went were on no row of the track's drum map.
function M.apply(clip, name)
  if type(clip) == "number" then clip = paw.clip(clip) end
  local beat = M.list[name]
  if not beat then error("no beat `" .. tostring(name) .. "`: there are " .. table.concat(M.names(), ", "), 0) end
  local bar = paw.time.bar()
  -- Sixteen steps make a bar of 4/4; other bars take the steps they hold.
  local step = 0.25
  local per_bar = math.floor(bar / step + 0.5)
  local add = {}
  for at = 0, clip.length - 1e-9, bar do
    for note, pattern in pairs(beat.rows) do
      for i = 1, math.min(per_bar, #pattern) do
        local v = VELOCITY[pattern:sub(i, i)]
        local start = at + (i - 1) * step
        if v and start < clip.length - 1e-9 then
          add[#add + 1] = { pitch = note, start = start, length = step, velocity = util.clamp(v, 1, 127) }
        end
      end
    end
  end
  -- Every note goes; those on no row of the drum map were not to be seen
  -- in the grid, so they are counted for the message.
  local rows = {}
  local info = require("drums").info(clip:get().track)
  for _, r in ipairs(info and info.rows or {}) do
    rows[r.note] = true
  end
  local remove, hidden = {}, 0
  for i, n in ipairs(clip:notes()) do
    remove[i] = i
    if info and not rows[n.pitch] then hidden = hidden + 1 end
  end
  clip:edit_notes({ remove = remove, add = add })
  return #add, hidden
end

return M
