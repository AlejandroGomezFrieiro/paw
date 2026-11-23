-- The writer of runtime/types/any-allowed.txt: the allow-list with each
-- count lowered to the `any` that the Teal declarations of this run have.
-- It runs after the writers of the declarations, which count them.
local model = require("apidoc.model")
local anys = require("apidoc.anys")

local function text(_: model.Model, run: model.Run): string
  return anys.lowered(run.anys, run.current)
end

local writer: model.Writer = {path = anys.PATH, text = text}

return writer
