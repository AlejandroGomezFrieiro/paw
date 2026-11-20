-- `paw.xml`: XML for the files of other programs, read and written by the
-- core (`paw.api.xml_decode`, `xml_encode`). An element is
-- `{ name, attr, order, children, text }`, with the methods below.
--
--   local root = assert(paw.xml.decode(text))
--   root:child("Transport"), root:all("Track"), root:text_of("title")
--   local el = paw.xml.element("Track", { id = "t1" }, { "id" })
--   el:add("Note", { time = 0 })
--   paw.xml.encode(root, { declaration = true, indent = "  " })
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local type types = require("paw.types")

local record M
  --- The value of an attribute: `decode` gives text; `encode` writes a
  --- number as the shortest text that reads back the same, and a boolean
  --- as `true` or `false`.
  type Value = string | number | boolean

  --- Where an element is in the text it was read from (`decode` with
  --- `spans`), in bytes from 1.
  type Span = types.XmlSpan

  --- An element: its name, its attributes (written in `order` first, then
  --- the others by name), its child elements, and the text directly in it
  --- (nil when there is none).
  record Element
    name: string
    attr: {string:Value}
    order: {string}
    children: {Element}
    text: string
    span: Span

    --- The first child with a name, or nil.
    child: function(self: Element, name: string): Element
    --- Every child with a name (every child without one).
    all: function(self: Element, name?: string): {Element}
    --- The text of a child, trimmed; nil when there is no such child.
    text_of: function(self: Element, name: string): string
    add: function(self: Element, name: string | Element, attr?: {string:Value}, order?: {string}): Element
  end

  --- What `decode` takes.
  record DecodeOptions
    spans: boolean
  end

  type EncodeOptions = types.XmlEncodeOptions
end

local type Element = M.Element

local metatable_of_element: metatable<Element> = { __index = M.Element }

--- A new element: `paw.xml.element("Track", { id = "t1", name = "Bass" })`.
--- Its attributes are written in the order of `order`, then the others by
--- name.
function M.element(name: string, attr?: {string:M.Value}, order?: {string}): Element
  return setmetatable({ name = name, attr = attr or {}, order = order, children = {} } as Element, metatable_of_element)
end

--- The root element of an XML text, or nil and what is wrong. `opts.spans`
--- keeps where each element is in the text, for `encode` with
--- `opts.source` (see `paw.api.xml_decode`).
function M.decode(text: string, opts?: M.DecodeOptions): Element, string
  -- The kernel sets the metatable of the elements' methods on each.
  local meta = metatable_of_element as metatable<types.XmlElement>
  return api.xml_decode(text, { spans = opts and opts.spans, meta = meta }) as (Element, string)
end

--- The XML text of an element: see `paw.api.xml_encode` for `opts`.
function M.encode(root: Element, opts?: M.EncodeOptions): string
  return api.xml_encode(root as types.XmlElement, opts)
end

--- Text made safe for XML, in text and in an attribute's quotes.
function M.escape(text: M.Value): string
  return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

--- The first child of an element with a name, or nil.
function M.child(el: Element, name: string): Element
  if not el then return nil end
  for _, c in ipairs(el.children) do
    if c.name == name then return c end
  end
end

--- Every child of an element with a name (every child without one).
function M.children(el: Element, name?: string): {Element}
  local out: {Element} = {}
  if not el then return out end
  for _, c in ipairs(el.children) do
    if not name or c.name == name then out[#out + 1] = c end
  end
  return out
end

--- The text of a child, trimmed; nil when there is no such child.
function M.text(el: Element, name: string): string
  local c = M.child(el, name)
  if not c then return nil end
  return ((c.text or ""):match("^%s*(.-)%s*$"))
end

--- The text of a child as a number, or nil.
function M.number(el: Element, name: string): number return tonumber(M.text(el, name) or "") end

-- The methods of an element.
M.Element.child = M.child
M.Element.all = M.children
M.Element.text_of = M.text

--- Add a child element and return it: `el:add("Note", { time = 0 })`, or
--- an element made before. `order` as in `element`.
function M.Element:add(name: string | Element, attr?: {string:M.Value}, order?: {string}): Element
  local c = name is Element and name or M.element(name as string, attr)
  c.order = order or c.order
  self.children[#self.children + 1] = c
  return c
end

return M
