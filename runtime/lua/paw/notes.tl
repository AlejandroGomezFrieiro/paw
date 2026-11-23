-- `paw.notes`: pure transforms of lists of notes. A transform takes a list
-- of notes and options, and gives a new list in the same order: one copy of
-- each note, with all of its fields. It changes no clip, so the key, the
-- gesture, the Ex command and an extension all use the same rule.
--
--   local moved = paw.notes.quantize(clip:notes(), { grid = 0.25, strength = 0.5 })
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local type types = require("paw.types")
local type util = require("paw.util")

local record M
  --- The options of `quantize`.
  record QuantizeOptions
    --- The step of the grid in beats (0.25 when not given).
    grid: number
    --- How far a note moves to the grid, from 0 to 1 (1 when not given).
    strength: number
    --- How much later every second grid line is, as a fraction of a step.
    swing: number
    --- Snap the lengths to the grid too, never shorter than one step.
    lengths: boolean
    --- Beats to add to a start to find its place on the grid: the start of
    --- the clip, for a grid of the song and not of the clip.
    offset: number
    --- The length of the clip: a note starts at least one step before its
    --- end and stops at its end.
    within: number
  end
end

--- A copy of a note with all of its fields (`meta` too, not copied deep).
local function copy(note: types.Note): types.Note
  local out: {string: util.Data} = {}
  for k, v in pairs(note as {string: util.Data}) do
    out[k] = v
  end
  return out as types.Note
end

--- Snap the starts of the notes to a grid. `opts.strength` says how far a
--- note moves, `opts.swing` moves every second grid line later, and
--- `opts.lengths` snaps the lengths too. With `opts.within`, a note stays
--- inside a clip of that length. No start goes below 0.
function M.quantize(notes: {types.Note}, opts?: M.QuantizeOptions): {types.Note}
  opts = opts or {}
  local grid, strength, swing = opts.grid or 0.25, opts.strength or 1, opts.swing or 0
  local offset, within = opts.offset or 0, opts.within
  local out: {types.Note} = {}
  for i, note in ipairs(notes) do
    local n = copy(note)
    -- The nearest grid line on the song's time, with its swing.
    local line = math.floor((n.start + offset) / grid + 0.5)
    local target = line * grid + (line % 2 == 1 and swing * grid or 0) - offset
    -- All the way lands on the line exactly, with no error of rounding.
    n.start = strength == 1 and target or n.start + (target - n.start) * strength
    if opts.lengths then
      local want = math.max(grid, math.floor(n.length / grid + 0.5) * grid)
      n.length = n.length + (want - n.length) * strength
    end
    if within then
      n.start = math.min(n.start, within - grid)
    end
    n.start = math.max(0, n.start)
    if within then
      n.length = math.min(n.length, within - n.start)
    end
    out[i] = n
  end
  return out
end

return M
