-- The writer of runtime/types/paw/role_props.d.tl: the props of each role
-- that the window paints (crates/paw-scene/src/props.rs), as it reads them.
local model = require("apidoc.model")
local names = require("apidoc.names")
local teal_type = require("apidoc.teal_type")

local function text(m: model.Model): string
  local file = m.props_rs
  local out: {string} = {
    "-- " .. names.HEADER,
    "-- Made from " .. file.path .. ": the props of each role that the",
    "-- window paints, as it reads them (`paw.api.scene_open`'s `props`).",
    "",
    "local record role_props",
    "   --- The props of a role: each record of this file is one.",
    "   interface Props",
    "   end",
  }
  for _, r in ipairs(file.records) do
    out[#out + 1] = ""
    for _, line in ipairs(r.doc) do
      out[#out + 1] = "   --- " .. line
    end
    out[#out + 1] = "   record " .. r.name .. " is Props"
    teal_type.fields(out, r, "      ", file)
    out[#out + 1] = "   end"
  end
  out[#out + 1] = "end"
  out[#out + 1] = ""
  out[#out + 1] = "return role_props"
  out[#out + 1] = ""
  return table.concat(out, "\n")
end

local writer: model.Writer = {path = "runtime/types/paw/role_props.d.tl", text = text}

return writer
