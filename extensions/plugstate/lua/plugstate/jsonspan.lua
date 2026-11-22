-- JSON with the place of each value in the text, so that a state can be
-- changed in one place and stay as it was everywhere else: the numbers
-- keep their digits, the keys their order, `{}` stays an object and `[]`
-- an array (a round trip through Lua tables keeps none of this).
--
-- `parse(text)` gives a node: `{ kind, s, e }` with `s` and `e` the first
-- and the last byte of the value. An object has `keys` (in order) and
-- `fields` (by key), an array `items`. `value(text, node)` decodes a node
-- with `paw.json`. `edit(text, { { node, new_text }, ... })` puts new text
-- in place of nodes.
local M = {}

local function skip(s, i) return s:find("[^ \t\r\n]", i) or #s + 1 end

local parse_value

local function parse_string(s, i)
  local j = i + 1
  while true do
    local c = s:find('["\\]', j)
    if not c then error("unfinished string in JSON", 0) end
    if s:byte(c) == 92 then
      j = c + 2
    else
      return c
    end
  end
end

function parse_value(s, i)
  i = skip(s, i)
  local c = s:sub(i, i)
  if c == "{" then
    local node = { kind = "object", s = i, keys = {}, fields = {} }
    i = skip(s, i + 1)
    if s:sub(i, i) == "}" then
      node.e = i
      return node
    end
    while true do
      if s:sub(i, i) ~= '"' then error("a key expected in JSON at " .. i, 0) end
      local ke = parse_string(s, i)
      local key = paw.json.decode(s:sub(i, ke))
      i = skip(s, ke + 1)
      if s:sub(i, i) ~= ":" then error("':' expected in JSON at " .. i, 0) end
      local v = parse_value(s, i + 1)
      node.keys[#node.keys + 1] = key
      node.fields[key] = v
      i = skip(s, v.e + 1)
      local d = s:sub(i, i)
      if d == "}" then
        node.e = i
        return node
      end
      if d ~= "," then error("',' expected in JSON at " .. i, 0) end
      i = skip(s, i + 1)
    end
  elseif c == "[" then
    local node = { kind = "array", s = i, items = {} }
    i = skip(s, i + 1)
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
      if d ~= "," then error("',' expected in JSON at " .. i, 0) end
      i = i + 1
    end
  elseif c == '"' then
    return { kind = "string", s = i, e = parse_string(s, i) }
  else
    local e = (s:find("[,%]}%s]", i) or #s + 1) - 1
    if e < i then error("a value expected in JSON at " .. i, 0) end
    return { kind = "scalar", s = i, e = e }
  end
end

--- The node of the JSON value that starts at `i` (default 1).
function M.parse(text, i) return parse_value(text, i or 1) end

--- The Lua value of a node.
function M.value(text, node) return (paw.json.decode(text:sub(node.s, node.e))) end

--- A node by a path of keys and indexes: `M.at(root, "preset", "scenes", 1)`.
function M.at(node, ...)
  for _, k in ipairs({ ... }) do
    if not node then return nil end
    if node.kind == "object" then
      node = node.fields[k]
    elseif node.kind == "array" then
      node = node.items[k]
    else
      return nil
    end
  end
  return node
end

--- The text with new text in place of nodes. The nodes must not overlap.
function M.edit(text, edits)
  table.sort(edits, function(a, b) return a[1].s > b[1].s end)
  for _, e in ipairs(edits) do
    text = text:sub(1, e[1].s - 1) .. e[2] .. text:sub(e[1].e + 1)
  end
  return text
end

--- An object with one field set: the node's text with the field's value
--- replaced, or the field added at the end.
function M.with_field(text, node, key, json)
  local f = node.fields[key]
  if f then return M.edit(text, { { f, json } }) end
  local inner = text:sub(node.s + 1, node.e - 1)
  local sep = inner:find("%S") and "," or ""
  return text:sub(1, node.e - 1) .. sep .. paw.json.encode(key) .. ":" .. json .. text:sub(node.e)
end

return M
