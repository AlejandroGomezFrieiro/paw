-- MIDI LSP for paw: a language server for music, plugged into `paw.lsp` as
-- any server is. This file is its configuration and nothing more: where the
-- engine is, how to start it, its settings as commands, and a list of what
-- every server says. See README.md.
paw.option.define("midilsp_cmd", "")        -- the engine to run; empty: $MIDI_LSP_ENGINE, else reaper-midi-lsp on PATH
paw.option.define("midilsp_suggest", true)  -- also start the engine's suggestion role, for completion
paw.option.define("midilsp_autostart", true) -- start when loaded, if the engine is found

local midilsp = require("midilsp")

paw.command("midilsp", function(ctx)
  local verb = ctx.args[1] or "info"
  if verb == "start" then
    midilsp.start(true)
  elseif verb == "stop" then
    midilsp.stop()
  else
    paw.ui.page("MIDI LSP", midilsp.info_lines())
  end
end, { desc = "MIDI LSP: `midilsp` says where the engine is and how it runs; `midilsp start`, `midilsp stop`", complete = { "info", "start", "stop" } })

paw.command("midilsp.preset", function(ctx)
  local name = ctx.args[1]
  if not name then return paw.notify("midilsp: preset " .. midilsp.settings().preset .. " (of " .. table.concat(midilsp.presets(), ", ") .. ")") end
  local ok, err = pcall(midilsp.set_preset, name)
  if not ok then paw.notify(tostring(err):gsub("^.-:%d+: ", ""), "error") end
end, { desc = "The rules MIDI LSP checks, as a profile: `midilsp.preset strict-counterpoint`", complete = function() return midilsp.presets() end })

paw.command("midilsp.rule", function(ctx)
  local id, state = ctx.args[1], ctx.args[2]
  if not id then return midilsp.pick_rules() end
  local ok, err = pcall(midilsp.set_rule, id, state == nil and "toggle" or state == "on")
  if not ok then paw.notify(tostring(err):gsub("^.-:%d+: ", ""), "error") end
end, { desc = "Switch a MIDI LSP rule on or off: `midilsp.rule parallel-perfect off`; alone, a list to toggle them in",
  complete = function() return midilsp.rule_ids() end })

paw.command("problems", function() midilsp.problems() end,
  { desc = "Every language server's diagnostics with their fixes: Enter goes to one, or applies a fix" })

-- On the core's `<leader>l` (language servers), beside `<leader>li`, `<leader>la` and `<leader>ll`.
paw.keymap.set("<leader>lD", "problems", { desc = "Problems: every server's diagnostics and fixes" })
paw.keymap.set("<leader>lR", "midilsp.rule", { desc = "MIDI LSP's rules, to switch on and off" })

if paw.opt.midilsp_autostart then midilsp.start(false) end
