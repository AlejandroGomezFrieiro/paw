-- Euclidean rhythms: spread `hits` as evenly as possible over `steps`.
local M = {}

--- A list of booleans, one per step.
function M.pattern(hits, steps, rotate)
  local out = {}
  for i = 0, steps - 1 do
    local at = (i + (rotate or 0)) % steps
    out[i + 1] = (at * hits) % steps < hits
  end
  return out
end

--- Notes for a pattern: one of `opts.pitch` on every hit, `opts.step` beats apart.
function M.notes(pattern, opts)
  local notes = {}
  for i, hit in ipairs(pattern) do
    if hit then
      notes[#notes + 1] = { pitch = opts.pitch, start = (i - 1) * opts.step, length = opts.step, velocity = opts.velocity }
    end
  end
  return notes
end

return M
