-- The writer of the records of runtime/lua/paw/types.tl that the kernel's
-- schema gives (`paw.api.api_schema`): the lines between its two marks
-- come from the Rust types, and the rest of the file stays as it is.
local model = require("apidoc.model")
local names = require("apidoc.names")

local PATH = "runtime/lua/paw/types.tl"
local BEGIN = "  -- The records below come from paw.api.api_schema (tools/apidoc.lua): change the Rust types."
local END = "  -- The end of the records from paw.api.api_schema."

local function doc(out: {string}, lines: {string}, pad: string)
  for _, line in ipairs(lines) do
    out[#out + 1] = pad .. "---" .. (line == "" and "" or " " .. line)
  end
end

local function text(m: model.Model, run: model.Run): string
  local head, tail = (run.current or ""):match(
    "^(.-" .. BEGIN:gsub("%p", "%%%0") .. "\n).-(" .. END:gsub("%p", "%%%0") .. ".*)$"
  )
  if not head then
    error(PATH .. ": the marks of the generated records are missing")
  end
  local out: {string} = {}
  for _, enum in ipairs(m.schema.enums) do
    out[#out + 1] = ""
    doc(out, enum.doc, "  ")
    out[#out + 1] = "  enum " .. enum.name
    for _, value in ipairs(enum.values) do
      out[#out + 1] = '    "' .. value .. '"'
    end
    out[#out + 1] = "  end"
  end
  for _, record in ipairs(m.schema.records) do
    out[#out + 1] = ""
    doc(out, record.doc, "  ")
    out[#out + 1] = "  record " .. record.name
    for _, f in ipairs(record.fields) do
      doc(out, f.doc, "    ")
      out[#out + 1] = "    " .. (names.KEYWORDS[f.name] and '["' .. f.name .. '"]' or f.name) .. ": " .. f.teal
    end
    out[#out + 1] = "  end"
  end
  return head .. table.concat(out, "\n") .. "\n\n" .. tail
end

local writer: model.Writer = {path = PATH, text = text}

return writer
