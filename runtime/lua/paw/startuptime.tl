-- `paw --startuptime FILE`: a line for each module that `require` loads
-- while paw starts. The kernel keeps the clock and writes the file
-- (crates/paw-core/src/startuptime.rs). It calls `wrap` before the runtime
-- loads, and `unwrap` after the first frame, so that `require` costs
-- nothing more later on. Without `--startuptime` this module is not loaded.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")

--- A module as `require` gives it: this module passes it on and never reads it.
local record Module
end
local type Require = function(name: string): Module

local record Globals
  require: Require
end
local G = _G as Globals

local record M
end

local raw: Require

--- Put a `require` that times each module it loads in place of the global one.
function M.wrap()
  if raw then
    return
  end
  raw = G.require
  local loaded = package.loaded
  G.require = function(name: string): Module
    if loaded[name] ~= nil then
      return raw(name)
    end
    api.startup_enter()
    local ok, result = pcall(raw, name) as (boolean, Module | string)
    api.startup_leave("require('" .. tostring(name) .. "')")
    if not ok then
      error(result, 0)
    end
    return result as Module
  end
end

--- Give back the `require` that `wrap` replaced.
function M.unwrap()
  if raw then
    G.require, raw = raw, nil
  end
end

return M
