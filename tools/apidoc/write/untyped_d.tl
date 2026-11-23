-- The writer of runtime/types/paw/untyped.d.tl: `paw.Untyped`, what is
-- still written in Lua, in a file of its own. A module of the runtime in
-- Teal is a part of the `paw` global, so it cannot name the global in its
-- types (the global requires the module): it takes the Lua that is not
-- ported yet as `local type Untyped = require("paw.untyped")`.
local model = require("apidoc.model")
local names = require("apidoc.names")
local anys = require("apidoc.anys")

local function text(_: model.Model, run: model.Run): string
  return table.concat(
    {
      "-- " .. names.HEADER,
      "-- What is still written in Lua: `paw.Untyped`. A module of the runtime in",
      '-- Teal names it `local type Untyped = require("paw.untyped")`, as it cannot',
      "-- name the `paw` global that requires it.",
      "",
      "local record Untyped",
      "   " .. anys.count(run.anys, "paw.Untyped", "metamethod __call: function(Untyped, ...: any): Untyped"),
      "   " .. anys.count(run.anys, "paw.Untyped", "metamethod __index: function(Untyped, any): Untyped"),
      "end",
      "",
      "return Untyped",
      "",
    },
    "\n"
  )
end

local writer: model.Writer = {path = "runtime/types/paw/untyped.d.tl", text = text}

return writer
