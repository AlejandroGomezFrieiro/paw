-- Files for state codecs: the bytes of a file. (Base64, little-endian
-- numbers and ZIP archives are the core's: paw.bytes, paw.zip.)
local M = {}

--- The bytes of a file, or nil and why.
function M.read_file(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local data = f:read("*a")
  f:close()
  return data
end

return M
