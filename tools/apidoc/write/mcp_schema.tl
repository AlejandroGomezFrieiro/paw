-- The writer of crates/paw-mcp/src/api_schema.json: the kernel's schema
-- (`paw.api.api_schema`) as the MCP server builds it in (`include_str!`),
-- so that the schemas of its tools take the types of the fields from the
-- Rust types (crates/paw-mcp/src/schema.rs).
local model = require("apidoc.model")

local writer: model.Writer = {
  path = "crates/paw-mcp/src/api_schema.json",
  text = function(m: model.Model, _run: model.Run): string return m.schema.json .. "\n" end,
}

return writer
