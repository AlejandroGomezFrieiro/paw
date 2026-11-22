-- Subprojects (nests): tracks with a timeline of their own, placed in the
-- song by nest clips. The kernel keeps them (crates/paw-core/src/model/nest.rs)
-- and saves each in `nests/<name>/` of the project's folder; this module
-- reads them. A subproject's tracks are usual tracks with a `nest`.
--
--   paw.nest.list()        -- every subproject, in the order they were made
--   paw.nest.get(id)       -- one subproject, or nil
--
-- To make one: `paw.api.nest_add({ name = "Bridge", length = 32 })`, then
-- `paw.api.track_add({ nest = id })` for each of its tracks.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local type types = require("paw.types")

local record M
end

--- Every subproject, in the order they were made: { id, name, length,
--- tempo, meter, master, tracks, kind, meta, used }.
function M.list(): {types.Nest}
  local out: {types.Nest} = {}
  for _, id in ipairs(api.nest_list()) do
    out[#out + 1] = api.nest_get(id)
  end
  return out
end

--- The subproject `id`, or nil when there is none.
function M.get(id: integer): types.Nest
  local ok, nest = pcall(api.nest_get, id) as (boolean, types.Nest)
  if ok then
    return nest
  end
  return nil
end

return M
