-- The writer of the rows of the runtime's events in docs/reference/events.md:
-- the rows between its two marks come from the descriptors that the modules
-- export, and the rest of the page stays as it is.
local model = require("apidoc.model")

local PATH = "docs/reference/events.md"
local BEGIN = "<!-- The rows below come from tools/apidoc.lua: change the descriptors, not the rows. -->"
local END = "<!-- The end of the rows from tools/apidoc.lua. -->"

local function text(m: model.Model, run: model.Run): string
  local head, tail = (run.current or ""):match(
    "^(.-" .. BEGIN:gsub("%p", "%%%0") .. "\n).-(" .. END:gsub("%p", "%%%0") .. ".*)$"
  )
  if not head then
    error(PATH .. ": the marks of the generated rows are missing")
  end
  local out = {head, "\n", "| Event | Payload | When | In Teal |\n", "| --- | --- | --- | --- |\n"}
  for _, row in ipairs(m.runtime_events) do
    out[#out + 1] = string.format("| `%s` | `%s` | %s | `%s` |\n", row.event, row.payload, row.when, row.teal)
  end
  out[#out + 1] = "\n"
  out[#out + 1] = tail
  return table.concat(out)
end

local writer: model.Writer = {path = PATH, text = text}

return writer
