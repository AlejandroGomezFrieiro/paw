-- chain-lsp for paw: the language server of the chain language, plugged
-- into `paw.lsp` as any server is. paw works the same without it. This file
-- is its configuration: the command and the start. See README.md.
local chainlsp = require("chainlsp")

local autostart = paw.option.define("chainlsp_autostart", true) -- start when loaded, if the server is found

paw.command(
  "chainlsp",
  function(ctx: paw.contracts.CommandContext)
    local verb = ctx.args[1] or "info"
    if verb == "start" then
      chainlsp.start(true)
    elseif verb == "stop" then
      chainlsp.stop()
    elseif verb == "check" then
      chainlsp.check()
    else
      paw.ui.page("chain-lsp", chainlsp.info_lines())
    end
  end,
  {
    desc = "chain-lsp: `chainlsp` says where the server is and which files it checks; `chainlsp start`, `stop`, `check`",
    complete = {"info", "start", "stop", "check"},
  }
)

if autostart:get() then
  chainlsp.start(false)
end
