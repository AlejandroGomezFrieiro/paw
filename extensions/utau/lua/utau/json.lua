-- JSON for what the extension writes to files and hands to
-- `paw-utau-engine --export`, read and written by the core (`paw.json`).
-- An empty table is an object unless it is marked with `M.array`.
local api = paw.api
local M = {}

--- Mark a table as an array, so that it is written as one even when empty.
M.array = api.json_array

--- The JSON text of a value; with `indent`, laid out on lines.
function M.encode(v, indent) return api.json_encode(v, indent ~= nil) end

--- The value of JSON text; an error when it is not JSON.
function M.decode(text)
  local v, why = api.json_decode(text)
  if v == nil and why then error(why, 0) end
  return v
end

return M
