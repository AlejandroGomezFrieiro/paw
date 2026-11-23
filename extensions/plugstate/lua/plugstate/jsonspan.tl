-- JSON with the place of each value in the text, so that a state can be
-- changed in one place and stay as it was everywhere else: the numbers
-- keep their digits, the keys their order, `{}` stays an object and `[]`
-- an array (a round trip through Lua tables keeps none of this).
--
-- `parse(text)` gives a node: `{ kind, s, e }` with `s` and `e` the first
-- and the last byte of the value. An object has `keys` (in order) and
-- `fields` (by key), an array `items`. `value(text, node)` decodes a node
-- with `paw.api.json_decode`. `edit(text, { { node, new_text }, ... })`
-- puts new text in place of nodes.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local api = paw.api
local type util = require("paw.util")

local record M
  --- The kinds of JSON value: a number, `true`, `false` and `null` are
  --- each a `scalar`.
  enum Kind
    "object"
    "array"
    "string"
    "scalar"
  end

  --- A JSON value in the text: its kind, its first and last byte, and
  --- what it holds.
  record Node
    kind: Kind
    s: integer
    e: integer
    --- An object: its keys in order, and the value of each.
    keys: {string}
    fields: {string: Node}
    --- An array: its items.
    items: {Node}
  end

  --- New text for a node.
  type Edit = {Node, string}

  --- A step of a path: a key of an object, or an index of an array.
  type Step = string | integer
end

local type Node = M.Node

local function skip(s: string, i: integer): integer
  return s:find("[^ \t\r\n]", i) or #s + 1
end

-- The end of the string that starts at `i`: its closing quote.
local function parse_string(s: string, i: integer): integer
  local j = i + 1
  while true do
    local c = s:find('["\\]', j)
    if not c then
      error("unfinished string in JSON", 0)
    end
    if s:byte(c) == 92 then
      j = c + 2
    else
      return c
    end
  end
end

local parse_value: function(s: string, i: integer): Node

local function parse_object(s: string, start: integer): Node
  local node: Node = {kind = "object", s = start, keys = {}, fields = {}}
  local i = skip(s, start + 1)
  if s:sub(i, i) == "}" then
    node.e = i
    return node
  end
  while true do
    if s:sub(i, i) ~= '"' then
      error("a key expected in JSON at " .. i, 0)
    end
    local ke = parse_string(s, i)
    local key = api.json_decode(s:sub(i, ke)) as string
    i = skip(s, ke + 1)
    if s:sub(i, i) ~= ":" then
      error("':' expected in JSON at " .. i, 0)
    end
    local v = parse_value(s, i + 1)
    node.keys[#node.keys + 1] = key
    node.fields[key] = v
    i = skip(s, v.e + 1)
    local d = s:sub(i, i)
    if d == "}" then
      node.e = i
      return node
    end
    if d ~= "," then
      error("',' expected in JSON at " .. i, 0)
    end
    i = skip(s, i + 1)
  end
end

local function parse_array(s: string, start: integer): Node
  local node: Node = {kind = "array", s = start, items = {}}
  local i = skip(s, start + 1)
  if s:sub(i, i) == "]" then
    node.e = i
    return node
  end
  while true do
    local v = parse_value(s, i)
    node.items[#node.items + 1] = v
    i = skip(s, v.e + 1)
    local d = s:sub(i, i)
    if d == "]" then
      node.e = i
      return node
    end
    if d ~= "," then
      error("',' expected in JSON at " .. i, 0)
    end
    i = i + 1
  end
end

parse_value = function(s: string, i: integer): Node
  i = skip(s, i)
  local c = s:sub(i, i)
  if c == "{" then
    return parse_object(s, i)
  elseif c == "[" then
    return parse_array(s, i)
  elseif c == '"' then
    return {kind = "string", s = i, e = parse_string(s, i)}
  end
  local e = (s:find("[,%]}%s]", i) or #s + 1) - 1
  if e < i then
    error("a value expected in JSON at " .. i, 0)
  end
  return {kind = "scalar", s = i, e = e}
end

--- The node of the JSON value that starts at `i` (default 1).
function M.parse(text: string, i?: integer): Node
  return parse_value(text, i or 1)
end

--- The value of a node, as `paw.api.json_decode` gives it.
function M.value(text: string, node: Node): util.Data
  return (api.json_decode(text:sub(node.s, node.e)) as util.Data)
end

--- The text of a node that holds a string, or nil when it is not one.
function M.text(text: string, node: Node): string
  if not node then
    return nil
  end
  local v = M.value(text, node)
  return v is string and v or nil
end

--- A node by a path of keys and indexes: `M.at(root, "preset", "scenes", 1)`.
function M.at(node: Node, ...: M.Step): Node
  for _, k in ipairs({...}) do
    if not node then
      return nil
    end
    if node.kind == "object" then
      node = node.fields[k as string]
    elseif node.kind == "array" then
      node = node.items[k as integer]
    else
      return nil
    end
  end
  return node
end

--- The text with new text in place of nodes. The nodes must not overlap.
function M.edit(text: string, edits: {M.Edit}): string
  table.sort(edits, function(a: M.Edit, b: M.Edit): boolean return a[1].s > b[1].s end)
  for _, e in ipairs(edits) do
    text = text:sub(1, e[1].s - 1) .. e[2] .. text:sub(e[1].e + 1)
  end
  return text
end

--- An object with one field set: the node's text with the field's value
--- replaced, or the field added at the end.
function M.with_field(text: string, node: Node, key: string, json: string): string
  local f = node.fields[key]
  if f then
    return M.edit(text, {{f, json}})
  end
  local inner = text:sub(node.s + 1, node.e - 1)
  local sep = inner:find("%S") and "," or ""
  return text:sub(1, node.e - 1) .. sep .. api.json_encode(key) .. ":" .. json .. text:sub(node.e)
end

return M
