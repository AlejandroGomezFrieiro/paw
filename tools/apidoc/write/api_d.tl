-- The writer of runtime/types/paw/api.d.tl: the functions of the kernel,
-- written in Rust, as the module `paw.api` that a module in Teal requires.
-- The type of each argument is its Rust type, or a `// @param name T` line
-- of its comment, and its result a `// @return T, U` line. T is in Teal's
-- notation and may name the records of runtime/lua/paw/types.tl as
-- `types.Name`. A function with no `@return` returns `any...`.
local model = require("apidoc.model")
local names = require("apidoc.names")
local anys = require("apidoc.anys")
local teal_type = require("apidoc.teal_type")

local function text(m: model.Model, run: model.Run): string
  local out: {string} = {
    "-- " .. names.HEADER,
    "-- The functions of the kernel, written in Rust (crates/paw-core/src/api/):",
    '-- `local api = require("paw.api")` in a module written in Teal.',
    "",
  }
  if m.has_types then
    out[#out + 1] = 'local type types = require("paw.types")'
    out[#out + 1] = 'local type kernel_events = require("paw.events.kernel")'
    out[#out + 1] = ""
  end
  out[#out + 1] = "local record api"
  out[#out + 1] = "   version: string"
  -- The kernel's other plain values (`limit_async`), by their Lua type.
  for _, plain in ipairs(m.kernel.plain) do
    out[#out + 1] = "   " .. plain.name .. ": " .. plain.type
  end
  for _, name in ipairs(m.kernel.names) do
    local f = m.kernel.functions[name]
    local sigs = f and teal_type.signatures(f) or {"function(...: any): any..."}
    for _, sig in ipairs(sigs) do
      out[#out + 1] = "   " .. anys.count(run.anys, "paw.api." .. name, name .. ": " .. sig)
    end
  end
  out[#out + 1] = "end"
  out[#out + 1] = ""
  out[#out + 1] = "return api"
  out[#out + 1] = ""
  return table.concat(out, "\n")
end

local writer: model.Writer = {path = "runtime/types/paw/api.d.tl", text = text}

return writer
