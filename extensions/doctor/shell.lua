-- What `paw doctor` runs (a script of `paw -l`): the checks that need nobody,
-- with the report on the standard output. It does not need the extension to be
-- in the configuration: it loads the modules from beside this file.
--
--   paw doctor [--seconds 20] [--plugin MT-PowerDrumKit]... [--only system,plugins] [--audio pipewire] ...
local here = debug.getinfo(1, "S").source:match("^@(.*)/shell%.lua$") or "."
package.path = here .. "/lua/?.lua;" .. here .. "/lua/?/init.lua;" .. package.path

local opts = { plugins = {} }
local argv = paw.api.env().argv
for _, arg in ipairs(argv) do
  local key, value = arg:match("^%-%-(%a+)=(.*)$")
  if key == "seconds" then
    opts.seconds = tonumber(value)
  elseif key == "plugin" then
    opts.plugins[#opts.plugins + 1] = value
  elseif key == "only" then
    opts.only = {}
    for id in value:gmatch("[^,]+") do
      opts.only[#opts.only + 1] = tonumber(id) or id
    end
  end
end
-- The plugins named in the configuration are tried unless some were asked for.
if #opts.plugins == 0 then opts.plugins = nil end

local doctor = require("doctor")
paw.api.quit(doctor.unattended(opts))
