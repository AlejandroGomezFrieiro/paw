-- paw's sample player: SFZ and Decent Sampler instruments played by the
-- extension's own CLAP plugin (`native/`), a kind of track for them, and
-- an instrument picker that lets each one be heard. See README.md.
paw.option.define("sampler_plugin_dir", "") -- where paw-sampler.clap is; `clap/` beside the extension when empty
paw.option.define("sampler_libraries", "") -- folders of instruments, separated by `:`

local sampler = require("sampler")
package.loaded["paw.sampler"] = sampler

-- The plugin this extension ships, found like any installed one.
local dir = sampler.plugin_dir()
if dir and paw.plugins and paw.plugins.add_dir then paw.plugins.add_dir(dir) end

require("sampler.commands")

-- `:checkhealth sampler`: the plugin it ships, found and made.
paw.health.register("sampler", function(h)
  local dir = sampler.plugin_dir()
  if not dir then
    return h.error("paw-sampler.clap not found", {
      "it is built with the extension's package: nix build .#paw-sampler",
      "or set paw.opt.sampler_plugin_dir to where it is",
    })
  end
  h.ok("the plugin in " .. dir)
  if sampler.available() then
    h.ok("it is among the devices")
  else
    h.error("it was found but not registered", ":plugins.rescan sampler")
  end
  h.info("instruments are looked for in " .. table.concat(sampler.roots(), ", "))
end, { desc = "the sample player" })
