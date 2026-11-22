-- Keys and scales: which pitches belong, how to move by scale degrees, and
-- the project's own key. The theory and the key itself are the core's
-- (`paw.harmony`); this keeps the names musicops has always given them.
--
-- A key is a table { root = 0..11, scale = "minor", steps = { 0, 2, 3, ... } }.
-- Everything that takes a key also takes its name: "D minor", "F# dorian",
-- "Bb" (major when no scale is named).
local H = paw.harmony
local M = {}

--- Every scale known by name, as semitones above the root.
M.scales = H.scales

M.names = H.scale_names
M.pitch_class = H.pitch_class
M.parse = H.parse_key
M.name = H.key_name
M.contains = H.in_key
M.snap = H.snap
M.degree = H.degree
M.pitch = H.degree_pitch
M.step = H.step

M.default = "C major"

--- The project's key, or nil when none is set.
M.project = H.project_key

--- The key to work in: the project's, or C major.
function M.current() return M.project() or M.parse(M.default) end

--- Set the project's key (one edit), or clear it with nil.
function M.set(spec)
  local key = H.set_key(spec)
  paw.emit("musicops.key", { key = key and M.name(key) or nil })
  return key
end

return M
