-- The XML of a DAWproject file, read and written by the core (`paw.xml`):
-- elements are `{ name, attr, order, children, text }` with `child`, `all`
-- and `add`; this says how the format writes them.
local M = {}

M.element = paw.xml.element

--- Read a document: its root element, or an error that says where it is broken.
function M.parse(text)
  local root, why = paw.xml.decode(text)
  if not root then error(why, 0) end
  return root
end

--- A number as the file writes it: 0.5, 120, 0.333333333333.
function M.number(n) return paw.xml.encode({ name = "n", attr = { v = n } }, { digits = 12 }):match('v="(.-)"') end

--- The text of a document whose root is `root`, laid out on lines.
function M.write(root)
  return paw.xml.encode(
    root,
    { declaration = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n', indent = "  ", digits = 12 }
  )
end

return M
