-- The writer of runtime/types/paw/partial.d.tl: the parts of the modules in
-- Lua that their doc comments type (`@type`), for a module of the runtime
-- in Teal, which cannot name the global: `local type partial =
-- require("paw.partial")`.
local model = require("apidoc.model")
local names = require("apidoc.names")
local anys = require("apidoc.anys")

-- `function<T>(a: A): R` as a metamethod of `self`: `function<T>(self, a: A): R`.
local function with_self(form: string, self: string): string
  local generics, rest = form:match("^function(<[^>]*>)%((.*)$")
  if not generics then
    generics, rest = "", form:match("^function%((.*)$")
  end
  return "function" .. generics .. "(" .. self .. (rest:match("^%)") and "" or ", ") .. rest
end

local function text(m: model.Model, run: model.Run): string
  local out: {string} = {
    "-- " .. names.HEADER,
    "-- The parts of the modules of the runtime in Lua that their doc comments",
    "-- type (`@type`): a module of the runtime in Teal takes the global as",
    "-- `partial.Paw`. What a module does not type is `paw.Untyped`.",
    "",
    'local type types = require("paw.types")',
    'local type contracts = require("paw.contracts")',
    'local type Untyped = require("paw.untyped")',
    "",
    "local record partial",
  }
  local paw_fields: {string} = {}
  for _, rec in ipairs(m.lua_types.records) do
    out[#out + 1] = "   record " .. rec.record
    for _, line in ipairs(rec.lines) do
      out[#out + 1] = "      " .. anys.count(run.anys, rec.name .. "." .. line[1], line[1] .. ": " .. line[2])
    end
    if rec.call then
      out[#out + 1] = "      metamethod __call: " .. with_self(rec.call, rec.record)
    end
    out[#out + 1] = "      "
      .. anys.count(run.anys, rec.name, "metamethod __index: function(" .. rec.record .. ", string): Untyped")
    out[#out + 1] = "   end"
    paw_fields[#paw_fields + 1] = rec.name:match("^paw%.(.*)$") .. ": " .. rec.record
  end
  for k, list in pairs(m.lua_types.top) do
    for _, t in ipairs(list) do
      paw_fields[#paw_fields + 1] = k .. ": " .. t
    end
  end
  table.sort(paw_fields)
  out[#out + 1] = "   --- The global `paw`, as far as the modules in Lua type it."
  out[#out + 1] = "   interface Paw"
  for _, line in ipairs(paw_fields) do
    out[#out + 1] = "      " .. line
  end
  out[#out + 1] = "   end"
  out[#out + 1] = "end"
  out[#out + 1] = ""
  out[#out + 1] = "return partial"
  out[#out + 1] = ""
  return table.concat(out, "\n")
end

local writer: model.Writer = {path = "runtime/types/paw/partial.d.tl", text = text}

return writer
