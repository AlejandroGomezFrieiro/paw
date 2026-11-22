-- TOML for the articulation maps, read and written by the core
-- (`paw.toml`, `paw.api.toml_decode`): what the maps need of it by name.
--
--   local t, err = toml.parse(text)     -- a table, or nil and "line 4: why"
--   toml.keys(t)                        -- its keys in the order written
--   toml.key("col-legno")               -- a key as TOML writes it
--   toml.inline({ m2 = "11.0" }, order) -- a value on one line
local M = {}

M.parse = paw.toml.decode

--- The keys of a table `parse` made, in the order they were written (a
--- map's articulations are numbered in that order); others by name.
function M.keys(t)
  local meta = getmetatable(t)
  local out = {}
  for i, k in ipairs(meta and meta.__keys or {}) do
    out[i] = k
  end
  if #out == 0 then
    for k in pairs(t) do
      out[#out + 1] = k
    end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  end
  return out
end

--- A value on one line: tables inline, keys in `order` first, then the
--- rest by name.
function M.inline(v, order)
  if type(v) == "table" and order then v = setmetatable(paw.util.merge(v), { __keys = order }) end
  return paw.toml.encode(v, true)
end

--- A key as TOML writes it: bare when it can be.
function M.key(text) return (M.inline({ [tostring(text)] = true }):match("^{%s*(.-)%s*=%s*true%s*}$")) end

return M
