-- plugstate: act on what a plugin keeps besides its parameters (the model
-- of an amp, an impulse response, an instrument file) without its window,
-- and keep named snapshots of a device's whole state. See README.md.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local type contracts = require("paw.contracts")

local plugstate = require("plugstate")
package.loaded["paw.plugstate"] = plugstate
require("plugstate.adapters")
require("plugstate.tone3000")
require("plugstate.soundshed")
require("plugstate.juceplugins")
require("plugstate.commands")
require("plugstate.tone3000_search")
require("plugstate.tone3000_auth")

paw.health.register(
  "plugstate",
  function(h: contracts.Health)
    local names: {string} = {}
    for _, a in ipairs(plugstate.adapters) do
      names[#names + 1] = a.name
    end
    h.ok("adapters: " .. table.concat(names, ", "))
    for _, root in ipairs(plugstate.roots()) do
      if #paw.api.read_dir(root) > 0 then
        h.ok("files in " .. root)
      else
        h.info("no files in " .. root)
      end
    end
  end,
  {desc = "plugin state: adapters and the library folders"}
)
