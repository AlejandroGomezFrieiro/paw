-- The writer of runtime/lua/paw/events/kernel.tl: the events of the kernel
-- (crates/paw-core/src/events.rs), each payload a record and each event a
-- descriptor, for `paw.on` and `paw.emit` in Teal.
local model = require("apidoc.model")
local names = require("apidoc.names")
local teal_type = require("apidoc.teal_type")

local function text(m: model.Model): string
  local file = m.events_rs
  local out: {string} = {
    "-- " .. names.HEADER,
    "-- Made from " .. file.path .. ": the events of the kernel, each a descriptor",
    "-- with the type of its payload, for `paw.on` and `paw.emit` in Teal:",
    "--",
    '--   local kernel = require("paw.events.kernel")',
    "--   paw.on(kernel.project_saved, function(p: kernel.Saved) print(p.path) end)",
    "",
    -- A value: each descriptor declares its name (`paw.events.event`).
    'local events = require("paw.events")',
    'local type types = require("paw.types")',
    "",
    "local record kernel",
    "   --- What every payload of the kernel may have: `restored` is true for a",
    "   --- change that undo or redo put back, which a handler that answers",
    "   --- edits with edits leaves alone.",
    "   interface Payload",
    "      restored: boolean",
    "   end",
  }
  for _, r in ipairs(file.records) do
    out[#out + 1] = ""
    for _, line in ipairs(r.doc) do
      out[#out + 1] = "   --- " .. line
    end
    out[#out + 1] = "   record " .. r.name .. " is Payload"
    teal_type.fields(out, r, "      ", file)
    out[#out + 1] = "   end"
  end
  out[#out + 1] = ""
  out[#out + 1] = "   --- An event as `paw.api.events_take` gives it."
  out[#out + 1] = "   record KernelEvent"
  out[#out + 1] = "      name: string"
  out[#out + 1] = "      payload: Payload"
  out[#out + 1] = "   end"
  out[#out + 1] = ""
  local records: {string: boolean} = {}
  for _, r in ipairs(file.records) do
    records[r.name] = true
  end
  local values: {string} = {}
  for _, v in ipairs(file.enums.KernelEvent or {}) do
    local t = v.teal or teal_type.field(v.type, records)
    if not t then
      error(file.path .. ": " .. v.name .. " (" .. v.type.text .. ") has no Teal type")
    end
    local key = v.serde:gsub("%.", "_")
    for _, line in ipairs(v.doc) do
      out[#out + 1] = "   --- " .. line
    end
    out[#out + 1] = "   " .. key .. ": events.Event<" .. t .. ">"
    values[#values + 1] = "kernel." .. key .. ' = events.event("' .. v.serde .. '")'
  end
  out[#out + 1] = "end"
  out[#out + 1] = ""
  for _, line in ipairs(values) do
    out[#out + 1] = line
  end
  out[#out + 1] = ""
  out[#out + 1] = "return kernel"
  out[#out + 1] = ""
  return table.concat(out, "\n")
end

local writer: model.Writer = {path = names.EVENTS_TL, text = text}

return writer
