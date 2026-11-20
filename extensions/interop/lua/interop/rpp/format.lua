-- REAPER's project format (.rpp, also track templates and FX chains) as a
-- tree that can be read, changed and written back.
--
--   <REAPER_PROJECT 0.1 "7.55/linux-x86_64" 1779302254 0     a block: `<NAME tokens`
--     TEMPO 135 4 4 0                                       a line: tokens
--     <RECORD_CFG                                           a block of base64 data lines
--       ZXZhdxgAAQ==
--     >
--   >
--
-- Every line keeps the text it was read from, and is written back as it was
-- unless its tokens changed, so an unchanged tree writes the same bytes
-- (indentation, quoting, number formatting and line endings included).
-- Lines that are new or changed are written the way REAPER writes them.
local M = {}

local Node = {}
Node.__index = Node
M.Node = Node

-- Tokens -----------------------------------------------------------------------

--- Split a line into tokens. A token is a run of non-blanks, or a stretch in
--- double quotes, single quotes or backticks (REAPER picks whichever quote
--- the text does not contain; there are no escapes).
function M.tokenize(s)
  local out, quotes, i, n = {}, nil, 1, #s
  while true do
    i = s:find("[^ \t]", i)
    if not i then break end
    local c = s:sub(i, i)
    if c == '"' or c == "'" or c == "`" then
      quotes = quotes or {}
      quotes[#out + 1] = c
      local j = s:find(c, i + 1, true)
      if not j then
        out[#out + 1] = s:sub(i + 1)
        break
      end
      out[#out + 1] = s:sub(i + 1, j - 1)
      i = j + 1
    else
      local j = s:find("[ \t]", i)
      out[#out + 1] = s:sub(i, (j or n + 1) - 1)
      if not j then break end
      i = j
    end
  end
  return out, quotes
end

--- A number as REAPER writes it: integers bare, others with up to 14
--- decimals and no trailing zeros (or fewer digits when they read back as
--- the same number: REAPER writes 441.6, not 441.60000000000002).
function M.number(x)
  if x ~= x or x == math.huge or x == -math.huge then return "0" end
  if x == math.floor(x) and math.abs(x) < 1e15 then return string.format("%d", x) end
  local s = string.format("%.14f", x):gsub("0+$", ""):gsub("%.$", "")
  for digits = 1, 16 do
    local short = string.format("%." .. digits .. "g", x)
    if not short:find("e") and tonumber(short) == tonumber(s) then
      if #short < #s then s = short end
      break
    end
  end
  if s == "-0" then s = "0" end
  return s
end

--- A token as REAPER writes it: bare unless it is empty, holds a blank or
--- starts with a quote; then in the first quote character it does not hold.
function M.quote(value, prefer)
  local s = type(value) == "number" and M.number(value) or tostring(value)
  if prefer and not s:find(prefer, 1, true) then return prefer .. s .. prefer end
  if s == "" then return '""' end
  local first = s:sub(1, 1)
  if not s:find("[ \t]") and first ~= '"' and first ~= "'" and first ~= "`" then return s end
  if not s:find('"', 1, true) then return '"' .. s .. '"' end
  if not s:find("'", 1, true) then return "'" .. s .. "'" end
  if not s:find("`", 1, true) then return "`" .. s .. "`" end
  return '"' .. s:gsub('"', "'") .. '"'
end

local function signature(tokens)
  local parts = {}
  for i, t in ipairs(tokens) do parts[i] = type(t) == "number" and M.number(t) or tostring(t) end
  return table.concat(parts, "\0")
end

-- Nodes --------------------------------------------------------------------------

--- A new line node: `rpp.line("TEMPO", 120, 4, 4)`.
function M.line(...)
  return setmetatable({ tokens = { ... } }, Node)
end

--- A new, empty block node: `rpp.block("TRACK", "{GUID}")`.
function M.block(...)
  return setmetatable({ tokens = { ... }, children = {} }, Node)
end

--- The node's name: its first token (a block's without the `<`).
function Node:name() return self.tokens[1] end

function Node:is_block() return self.children ~= nil end

--- Token `i` after the name, as a string (or nil).
function Node:arg(i)
  local v = self.tokens[i + 1]
  if v == nil then return nil end
  return type(v) == "number" and M.number(v) or v
end

--- Token `i` after the name, as a number (or nil).
function Node:argn(i) return tonumber(self.tokens[i + 1]) end

--- Replace the tokens after the name.
function Node:set_args(...)
  local name = self.tokens[1]
  self.tokens = { name, ... }
  return self
end

--- Always quote these arguments (1 is the first after the name), as REAPER
--- does for some fields, such as file paths, whatever they hold.
function Node:quoted(...)
  self.quotes = self.quotes or {}
  for _, i in ipairs({ ... }) do self.quotes[i + 1] = '"' end
  return self
end

--- The first child named `name` (a line or a block), and its index.
function Node:child(name)
  for i, c in ipairs(self.children or {}) do
    if c.tokens[1] == name then return c, i end
  end
end

--- Every child named `name`, or every child when `name` is nil.
function Node:all(name)
  local out = {}
  for _, c in ipairs(self.children or {}) do
    if name == nil or c.tokens[1] == name then out[#out + 1] = c end
  end
  return out
end

--- Child blocks only, optionally of one name.
function Node:blocks(name)
  local out = {}
  for _, c in ipairs(self.children or {}) do
    if c.children and (name == nil or c.tokens[1] == name) then out[#out + 1] = c end
  end
  return out
end

--- Argument `i` (default 1) of the first child line named `key`, as a string.
function Node:get(key, i)
  local c = self:child(key)
  return c and c:arg(i or 1)
end

--- The same as a number.
function Node:getn(key, i)
  local c = self:child(key)
  return c and c:argn(i or 1)
end

--- Set the first child line named `key` to these arguments, adding it at
--- the end (or before `opts.before`, a child name) when there is none.
function Node:set(key, ...)
  local c = self:child(key)
  if c then
    c:set_args(...)
    return c
  end
  return self:add(M.line(key, ...))
end

--- Add a child at the end, or at a 1-based position.
function Node:add(child, index)
  if index then table.insert(self.children, index, child) else self.children[#self.children + 1] = child end
  return child
end

--- Add a child just before the first child named `name` (at the end if none).
function Node:add_before(name, child)
  local _, i = self:child(name)
  return self:add(child, i)
end

function Node:remove(child)
  for i, c in ipairs(self.children) do
    if c == child then return table.remove(self.children, i) end
  end
end

--- Remove every child named `name`.
function Node:remove_all(name)
  for i = #self.children, 1, -1 do
    if self.children[i].tokens[1] == name then table.remove(self.children, i) end
  end
end

--- The data lines of a block (lines that are one token, such as base64),
--- split into groups where REAPER started a new group: after a line shorter
--- than `width` (default 128, the width REAPER writes plugin states in) or
--- ending in padding. Plugin states are written as several separately
--- encoded parts this way.
function Node:data_groups(width)
  width = width or 128
  local groups, current = {}, {}
  for _, c in ipairs(self.children) do
    if not c.children and #c.tokens == 1 then
      local s = c.tokens[1]
      current[#current + 1] = s
      if #s < width or s:sub(-1) == "=" then
        groups[#groups + 1] = table.concat(current)
        current = {}
      end
    end
  end
  if #current > 0 then groups[#groups + 1] = table.concat(current) end
  return groups
end

--- All data lines joined.
function Node:data() return table.concat(self:data_groups()) end

--- Replace the data lines with these base64 groups, each starting on a new
--- line and cut into lines of `width` characters (REAPER uses 128 for
--- plugin states).
function Node:set_data(groups, width)
  if type(groups) == "string" then groups = { groups } end
  width = width or 128
  for i = #self.children, 1, -1 do
    local c = self.children[i]
    if not c.children and #c.tokens == 1 and c.tokens[1]:match("^[%w+/=]+$") then table.remove(self.children, i) end
  end
  local at = 1
  for _, text in ipairs(groups) do
    for i = 1, #text, width do
      self:add(M.line(text:sub(i, i + width - 1)), at)
      at = at + 1
    end
  end
  return self
end

--- Walk the subtree depth first, calling fn(node, parent) for every node.
function Node:walk(fn, parent)
  fn(self, parent)
  for _, c in ipairs(self.children or {}) do c:walk(fn, self) end
end

-- Parsing ----------------------------------------------------------------------

local Doc = {}
Doc.__index = function(self, key)
  if key == "project" then return self:child("REAPER_PROJECT") end
  return Doc[key] or Node[key]
end

--- Parse text into a document: a node whose children are the top-level
--- nodes (for a project, one `REAPER_PROJECT` block, reachable as
--- `doc.project`). Never fails: what does not fit the format is kept as
--- plain lines.
function M.parse(text)
  local doc = setmetatable({ tokens = {}, children = {}, doc = true }, Doc)
  local stack = { doc }
  local pos, n = 1, #text
  while pos <= n do
    local eol = text:find("\n", pos, true)
    local raw = text:sub(pos, eol or n)
    pos = (eol or n) + 1
    local content = raw:gsub("[\r\n]+$", ""):match("^[ \t]*(.-)[ \t]*$")
    local top = stack[#stack]
    if content:sub(1, 1) == "<" then
      local tokens, quotes = M.tokenize(content:sub(2))
      local node = setmetatable({ tokens = tokens, quotes = quotes, children = {}, raw = raw }, Node)
      node.sig = signature(node.tokens)
      top.children[#top.children + 1] = node
      stack[#stack + 1] = node
    elseif content == ">" and #stack > 1 then
      top.close = raw
      stack[#stack] = nil
    else
      local tokens, quotes = M.tokenize(content)
      local node = setmetatable({ tokens = tokens, quotes = quotes, raw = raw }, Node)
      node.sig = signature(node.tokens)
      top.children[#top.children + 1] = node
    end
  end
  -- Blocks left open at the end of the file get no closing line, as read.
  for i = #stack, 2, -1 do stack[i].close = stack[i].close or "" end
  doc.eol = text:match("\r\n") and "\r\n" or "\n"
  return doc
end

--- Read and parse a file.
function M.read(path)
  local file, err = io.open(path, "rb")
  if not file then error("cannot read " .. path .. ": " .. tostring(err), 2) end
  local text = file:read("*a")
  file:close()
  return M.parse(text)
end

-- Writing ----------------------------------------------------------------------

local function emit(node, depth, out, eol)
  local indent = string.rep("  ", depth)
  if node.raw and node.sig == signature(node.tokens) then
    out[#out + 1] = node.raw
  else
    local parts, quotes = {}, node.quotes or {}
    for i, t in ipairs(node.tokens) do parts[i] = M.quote(t, quotes[i]) end
    out[#out + 1] = indent .. (node.children and "<" or "") .. table.concat(parts, " ") .. eol
  end
  if node.children then
    for _, c in ipairs(node.children) do emit(c, depth + 1, out, eol) end
    out[#out + 1] = node.close or (indent .. ">" .. eol)
  end
end

--- Write a document (or a single node) back to text.
function M.write(node)
  local out, eol = {}, node.eol or "\n"
  if node.doc then
    for _, c in ipairs(node.children) do emit(c, 0, out, eol) end
  else
    emit(node, 0, out, eol)
  end
  return table.concat(out)
end

--- Write a document to a file, through a temporary file and a rename.
function M.save(doc, path)
  local tmp = path .. ".tmp"
  local file = assert(io.open(tmp, "wb"))
  file:write(M.write(doc))
  file:close()
  assert(os.rename(tmp, path))
end

--- A new, empty document whose lines will end in `eol` (default "\n").
function M.document(eol)
  return setmetatable({ tokens = {}, children = {}, doc = true, eol = eol or "\n" }, Doc)
end

return M
