-- XML as JUCE plugins keep it (`AudioProcessor::copyXmlToBinary`,
-- `ValueTree::createXml`, `XmlElement::writeTo`), read into the trees of
-- `plugstate.juce`: an element is a node, its attributes are string
-- properties. The core reads and writes the XML (`paw.xml`): what is not
-- changed is written back byte for byte, through where each element was
-- in the text; a changed or new element is written on one line, as JUCE
-- writes it.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local juce = require("plugstate.juce")
local type xml = require("paw.xml")

local type Tree = juce.Tree

local record M
  --- An XML text as a tree, and what is around the root element:
  --- `before` (the declaration and what else is before it), `after`, and
  --- the whole text as read (`source`).
  record Doc
    root: Tree
    before: string
    after: string
    source: string
  end
end

--- A number as JUCE writes a double in text (`serialiseDouble`): a whole
--- number with ".0", else the shortest text that reads back the same.
function M.number(v: number): string
  if v ~= v then
    return "nan"
  end
  if v == math.huge then
    return "inf"
  end
  if v == -math.huge then
    return "-inf"
  end
  local a = math.abs(v)
  if a < 1e6 and a > 1e-5 and v == math.floor(v) then
    return string.format("%.1f", v)
  end
  if v == 0 then
    return "0.0"
  end
  for digits = 1, 17 do
    local text = string.format("%." .. digits .. "g", v)
    if tonumber(text) == v then
      return text
    end
  end
  return string.format("%.17g", v)
end

--- The text of a stored var, as `var::toString` gives it.
function M.text_of(raw: string): string
  local v = juce.value(raw)
  local kind = juce.kind(raw)
  if v == nil then
    return ""
  end
  if v is boolean then
    return v and "1" or "0"
  end
  if v is number then
    if kind == "double" then
      return M.number(v)
    end
    return string.format("%d", math.floor(v))
  end
  if v is juce.Blob then
    return v.binary and juce.encode64(v.binary) or ""
  end
  return v
end

-- --- reading and writing: the core's XML (`paw.xml`) ----------------------------------

--- A node of `plugstate.juce` from an element of `paw.xml`: attributes as
--- string properties; `_span` and `_text` keep where it was and its text as
--- read, so that what does not change is written back as it was.
local function node_of(el: xml.Element): Tree
  local node: Tree = {type = el.name, props = {}, children = {}, xml = true, _span = el.span, _text = el.text}
  for _, k in ipairs(el.order) do
    node.props[#node.props + 1] = {k, juce.raw(el.attr[k], "string")}
  end
  for i, c in ipairs(el.children) do
    node.children[i] = node_of(c)
  end
  -- Text that is only the layout between children is none.
  if el.text and el.text:find("%S") then
    node.text = el.text
  end
  node._text0 = node.text
  return node
end

--- The tree of an XML text, and what is around it: `{ root, before, after }`
--- (`before`: the declaration and what else is before the root element).
function M.parse(s: string): M.Doc
  local el, why = paw.xml.decode(s, {spans = true})
  if not el then
    error(why, 0)
  end
  local root = node_of(el)
  return {root = root, before = s:sub(1, el.span.from - 1), after = s:sub(el.span.to + 1), source = s}
end

local function element_of(node: Tree): xml.Element
  local el: xml.Element = {name = node.type, attr = {}, order = {}, children = {}, span = node._span}
  for i, p in ipairs(node.props) do
    el.order[i] = p[1]
    el.attr[p[1]] = M.text_of(p[2])
  end
  for i, c in ipairs(node.children) do
    el.children[i] = element_of(c)
  end
  -- Text as read, layout and all, while it did not change.
  if node.text == node._text0 then
    el.text = node._text
  else
    el.text = node.text
  end
  return el
end

--- The text of a document from `parse`, with what was around its root.
--- What did not change is written as it was read, byte for byte; what
--- changed, on one line.
function M.write(doc: M.Doc): string
  local el = element_of(doc.root)
  if doc.source and el.span then
    return paw.xml.encode(el, {source = doc.source})
  end
  return (doc.before or "") .. paw.xml.encode(el, {source = doc.source}) .. (doc.after or "")
end

--- A new element (a tree with `xml` set, so its numbers are written as
--- text): `props` is `{ { name, value }, ... }`.
function M.tree(kind: string, props?: {juce.PropSpec}, children?: {Tree}): Tree
  local node = juce.tree(kind, nil, children)
  node.xml = true
  for _, p in ipairs(props or {}) do
    juce.set(node, p[1], p[2], p[3])
  end
  return node
end

return M
