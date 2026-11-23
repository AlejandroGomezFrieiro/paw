-- The mix findings as a language server run in this process: attached to
-- the `mix` subject, it publishes the last measurement's findings as
-- diagnostics, each about the part it names (the master for the whole
-- mix) at the beat it names, with a fix wherever a finding says by how much
-- to lower a fader. So `:diagnostics`, `]d`, the marks on strips and
-- headers, and `<leader>la` agree with the mix report.
local mixdiag = require("mixdiag")
local A = paw.address

local M = {}

local SEVERITY = { error = 1, warn = 2, info = 3, hint = 4 }

local ctx, doc

-- A finding as a diagnostic of LSP's shape, with this program's location
-- and fixes in `data`.
function M.diagnostic(f)
  local part = f.part or 0
  local ok = pcall(paw.api.part_get, part)
  local uri = ok and A.part(part) or A.project()
  local location = { uri = uri, selector = f.beat and { time = { f.beat, f.beat } } or nil }
  local fixes = {}
  if f.lower and ok then
    local name = paw.api.part_get(part, "name")
    local now = paw.api.part_get(part, "volume")
    fixes[1] = {
      title = string.format("Lower %s by %.1f dB", part == 0 and "the master" or name, f.lower),
      edit = { { uri = A.part(part), set = { volume = now - f.lower } } },
    }
  end
  return {
    range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
    severity = SEVERITY[f.severity] or 3,
    code = f.rule,
    source = "mixdiag",
    message = mixdiag.format(f),
    data = { location = location, fixes = fixes, finding = f },
  }
end

--- Publish the findings there are now (none before a measurement).
function M.publish()
  if not (ctx and doc) then return end
  local list = {}
  for _, f in ipairs(mixdiag.findings or {}) do
    list[#list + 1] = M.diagnostic(f)
  end
  ctx.notify("textDocument/publishDiagnostics", { uri = doc, diagnostics = list })
end

-- The handlers `paw.lsp` calls, as it would a server's methods.
M.server = {
  initialize = function(_, c)
    ctx = c
    return { serverInfo = { name = "mixdiag" }, capabilities = { paw = { subjects = { "mix" } } } }
  end,
  ["textDocument/didOpen"] = function(params)
    doc = params.textDocument.uri
    M.publish()
  end,
  -- What was measured holds until it is measured again, whatever the faders do since.
  ["textDocument/didChange"] = function() end,
  ["textDocument/didClose"] = function() doc = nil end,
  shutdown = function()
    ctx, doc = nil, nil
  end,
}

return M
