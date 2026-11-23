-- The writer of runtime/types/paw/opts.d.tl: `paw.opt`, each option that
-- the runtime defines by its type, and any other by its name.
local model = require("apidoc.model")
local names = require("apidoc.names")

-- The Teal type of an option: its Lua types, `integer` for a whole number.
local function option_type(option: model.Option): string
  local out: {string} = {}
  for _, t in ipairs(option.types) do
    if t == "number" then
      out[#out + 1] = option.integer and "integer" or "number"
    elseif t == "table" then
      out[#out + 1] = "{string | number}"
    else
      out[#out + 1] = t
    end
  end
  return table.concat(out, " | ")
end

local function text(m: model.Model): string
  local out: {string} = {
    "-- " .. names.HEADER,
    "-- `paw.opt`: each option that the runtime defines (`paw.option.list`), by",
    "-- the type of its default and its spec, and any other option by its name.",
    "",
    "local record Opts",
    "   --- What an option holds: text, a number, true or false, or a list.",
    "   type Value = string | number | boolean | {string | number}",
    "",
  }
  for _, option in ipairs(m.options) do
    out[#out + 1] = "   " .. option.name .. ": " .. option_type(option)
  end
  out[#out + 1] = "   metamethod __index: function(Opts, string): Value"
  out[#out + 1] = "   metamethod __newindex: function(Opts, string, Value)"
  out[#out + 1] = "end"
  out[#out + 1] = ""
  out[#out + 1] = "return Opts"
  out[#out + 1] = ""
  return table.concat(out, "\n")
end

local writer: model.Writer = {path = "runtime/types/paw/opts.d.tl", text = text}

return writer
