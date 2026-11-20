-- `paw.xml`: XML for the files of other programs, read and written by the
-- core (`paw.api.xml_decode`, `xml_encode`). An element is
-- `{ name, attr, order, children, text }`, with the methods below.
--
--   local root = assert(paw.xml.decode(text))
--   root:child("Transport"), root:all("Track"), root:text_of("title")
--   local el = paw.xml.element("Track", { id = "t1" }, { "id" })
--   el:add("Note", { time = 0 })
--   paw.xml.encode(root, { declaration = true, indent = "  " })
local api = paw.api

local M = {}

local Element = {}
Element.__index = Element
M.Element = Element

--- A new element: `paw.xml.element("Track", { id = "t1", name = "Bass" })`.
--- Its attributes are written in the order of `order`, then the others by
--- name.
function M.element(name, attr, order)
  return setmetatable({ name = name, attr = attr or {}, order = order, children = {} }, Element)
end

--- The root element of an XML text, or nil and what is wrong. `opts.spans`
--- keeps where each element is in the text, for `encode` with
--- `opts.source` (see `paw.api.xml_decode`).
function M.decode(text, opts)
  return api.xml_decode(text, { spans = opts and opts.spans, meta = Element })
end

--- The XML text of an element: see `paw.api.xml_encode` for `opts`.
function M.encode(root, opts) return api.xml_encode(root, opts) end

--- Text made safe for XML, in text and in an attribute's quotes.
function M.escape(text)
  return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

--- The first child of an element with a name, or nil.
function M.child(el, name)
  if not el then return nil end
  for _, c in ipairs(el.children) do
    if c.name == name then return c end
  end
end
Element.child = M.child

--- Every child of an element with a name (every child without one).
function M.children(el, name)
  local out = {}
  if not el then return out end
  for _, c in ipairs(el.children) do
    if not name or c.name == name then out[#out + 1] = c end
  end
  return out
end
Element.all = M.children

--- The text of a child, trimmed; nil when there is no such child.
function M.text(el, name)
  local c = M.child(el, name)
  if not c then return nil end
  return ((c.text or ""):match("^%s*(.-)%s*$"))
end
Element.text_of = M.text

--- The text of a child as a number, or nil.
function M.number(el, name) return tonumber(M.text(el, name) or "") end

--- Add a child element and return it: `el:add("Note", { time = 0 })`, or
--- an element made before. `order` as in `element`.
function Element:add(name, attr, order)
  local c = type(name) == "table" and name or M.element(name, attr)
  c.order = order or c.order
  self.children[#self.children + 1] = c
  return c
end

return M
