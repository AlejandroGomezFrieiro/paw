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
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local record M
  --- A token of a line: text as read, or a number that a script set.
  type Token = string | number

  --- A line or a block of the file, or a document (the top of a file).
  record Node
    --- The name, then the arguments.
    tokens: {Token}
    --- The quote character of each token that was quoted, by place.
    quotes: {integer: string}
    --- The lines and blocks in a block; nil for a line.
    children: {Node}
    --- The text the node was read from, and the signature of its tokens
    --- then: the node is written as `raw` while its tokens give `sig`.
    raw: string
    sig: string
    --- The closing line of a block as read ("" when the file ended first).
    close: string
    --- A document: its children are the top-level nodes, written with
    --- `eol` at the end of each line.
    doc: boolean
    eol: string
    --- A document's `REAPER_PROJECT` block, or nil.
    project: Node

    name: function(self: Node): string
    is_block: function(self: Node): boolean
    arg: function(self: Node, i: integer): string
    argn: function(self: Node, i: integer): number
    set_args: function(self: Node, ...: Token): Node
    quoted: function(self: Node, ...: integer): Node
    child: function(self: Node, name: string): Node, integer
    all: function(self: Node, name?: string): {Node}
    blocks: function(self: Node, name?: string): {Node}
    get: function(self: Node, key: string, i?: integer): string
    getn: function(self: Node, key: string, i?: integer): number
    set: function(self: Node, key: string, ...: Token): Node
    add: function(self: Node, child: Node, index?: integer): Node
    add_before: function(self: Node, name: string, child: Node): Node
    remove: function(self: Node, child: Node): Node
    remove_all: function(self: Node, name: string)
    data_groups: function(self: Node, width?: integer): {string}
    data: function(self: Node): string
    set_data: function(self: Node, groups: string | {string}, width?: integer): Node
    walk: function(self: Node, fn: function(node: Node, parent: Node), parent?: Node)
  end
end

local type Token = M.Token
local type Node = M.Node

local node_meta: metatable<Node> = {__index = M.Node}

local PROJECT = "REAPER_PROJECT"

-- Tokens -----------------------------------------------------------------------

--- Split a line into tokens. A token is a run of non-blanks, or a stretch in
--- double quotes, single quotes or backticks (REAPER picks whichever quote
--- the text does not contain; there are no escapes).
function M.tokenize(s: string): {Token}, {integer: string}
  local out: {Token} = {}
  local quotes: {integer: string}
  local i, n = 1, #s
  while true do
    i = s:find("[^ \t]", i)
    if not i then
      break
    end
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
      if not j then
        break
      end
      i = j
    end
  end
  return out, quotes
end

--- A number as REAPER writes it: integers bare, others with up to 14
--- decimals and no trailing zeros (or fewer digits when they read back as
--- the same number: REAPER writes 441.6, not 441.60000000000002).
function M.number(x: number): string
  if x ~= x or x == math.huge or x == -math.huge then
    return "0"
  end
  if x == math.floor(x) and math.abs(x) < 1e15 then
    return string.format("%d", x)
  end
  local s = string.format("%.14f", x):gsub("0+$", ""):gsub("%.$", "")
  for digits = 1, 16 do
    local short = string.format("%." .. digits .. "g", x)
    if not short:find("e") and tonumber(short) == tonumber(s) then
      if #short < #s then
        s = short
      end
      break
    end
  end
  if s == "-0" then
    s = "0"
  end
  return s
end

--- A token as text: a number as REAPER writes it.
local function text_of(t: Token): string
  if t is number then
    return M.number(t)
  end
  return tostring(t)
end

--- A token as REAPER writes it: bare unless it is empty, holds a blank or
--- starts with a quote; then in the first quote character it does not hold.
function M.quote(value: Token, prefer?: string): string
  local s = text_of(value)
  if prefer and not s:find(prefer, 1, true) then
    return prefer .. s .. prefer
  end
  if s == "" then
    return '""'
  end
  local first = s:sub(1, 1)
  if not s:find("[ \t]") and first ~= '"' and first ~= "'" and first ~= "`" then
    return s
  end
  if not s:find('"', 1, true) then
    return '"' .. s .. '"'
  end
  if not s:find("'", 1, true) then
    return "'" .. s .. "'"
  end
  if not s:find("`", 1, true) then
    return "`" .. s .. "`"
  end
  return '"' .. s:gsub('"', "'") .. '"'
end

local function signature(tokens: {Token}): string
  local parts: {string} = {}
  for i, t in ipairs(tokens) do
    parts[i] = text_of(t)
  end
  return table.concat(parts, "\0")
end

-- Nodes --------------------------------------------------------------------------

--- A new line node: `rpp.line("TEMPO", 120, 4, 4)`.
function M.line(...: Token): Node
  return setmetatable({tokens = {...}} as Node, node_meta)
end

--- A new, empty block node: `rpp.block("TRACK", "{GUID}")`.
function M.block(...: Token): Node
  return setmetatable({tokens = {...}, children = {}} as Node, node_meta)
end

--- The node's name: its first token (a block's without the `<`).
function Node:name(): string
  local t = self.tokens[1]
  if t == nil then
    return nil
  end
  return text_of(t)
end

function Node:is_block(): boolean
  return self.children ~= nil
end

--- Token `i` after the name, as a string (or nil).
function Node:arg(i: integer): string
  local v = self.tokens[i + 1]
  if v == nil then
    return nil
  end
  return text_of(v)
end

--- Token `i` after the name, as a number (or nil).
function Node:argn(i: integer): number
  return tonumber(self.tokens[i + 1])
end

--- Replace the tokens after the name.
function Node:set_args(...: Token): Node
  local name = self.tokens[1]
  self.tokens = {name, ...}
  return self
end

--- Always quote these arguments (1 is the first after the name), as REAPER
--- does for some fields, such as file paths, whatever they hold.
function Node:quoted(...: integer): Node
  self.quotes = self.quotes or {}
  for _, i in ipairs({...}) do
    self.quotes[i + 1] = '"'
  end
  return self
end

--- The first child named `name` (a line or a block), and its index.
function Node:child(name: string): Node, integer
  for i, c in ipairs(self.children or {}) do
    if c.tokens[1] == name then
      return c, i
    end
  end
end

--- Every child named `name`, or every child when `name` is nil.
function Node:all(name?: string): {Node}
  local out: {Node} = {}
  for _, c in ipairs(self.children or {}) do
    if name == nil or c.tokens[1] == name then
      out[#out + 1] = c
    end
  end
  return out
end

--- Child blocks only, optionally of one name.
function Node:blocks(name?: string): {Node}
  local out: {Node} = {}
  for _, c in ipairs(self.children or {}) do
    if c.children and (name == nil or c.tokens[1] == name) then
      out[#out + 1] = c
    end
  end
  return out
end

--- Argument `i` (default 1) of the first child line named `key`, as a string.
function Node:get(key: string, i?: integer): string
  local c = self:child(key)
  return c and c:arg(i or 1)
end

--- The same as a number.
function Node:getn(key: string, i?: integer): number
  local c = self:child(key)
  return c and c:argn(i or 1)
end

--- Set the first child line named `key` to these arguments, adding it at
--- the end when there is none.
function Node:set(key: string, ...: Token): Node
  local c = self:child(key)
  if c then
    c:set_args(...)
    return c
  end
  return self:add(M.line(key, ...))
end

--- A document's `project` is its first `REAPER_PROJECT` block: set again
--- after each change of its children.
local function find_project(self: Node)
  if self.doc then
    self.project = self:child(PROJECT)
  end
end

--- Add a child at the end, or at a 1-based position.
function Node:add(child: Node, index?: integer): Node
  if index then
    table.insert(self.children, index, child)
  else
    self.children[#self.children + 1] = child
  end
  find_project(self)
  return child
end

--- Add a child just before the first child named `name` (at the end if none).
function Node:add_before(name: string, child: Node): Node
  local _, i = self:child(name)
  return self:add(child, i)
end

function Node:remove(child: Node): Node
  for i, c in ipairs(self.children) do
    if c == child then
      local removed = table.remove(self.children, i)
      find_project(self)
      return removed
    end
  end
end

--- Remove every child named `name`.
function Node:remove_all(name: string)
  for i = #self.children, 1, -1 do
    if self.children[i].tokens[1] == name then
      table.remove(self.children, i)
    end
  end
  find_project(self)
end

--- A data line: one token of text (base64, for example).
local function data_text(c: Node): string
  if not c.children and #c.tokens == 1 then
    return text_of(c.tokens[1])
  end
end

--- The data lines of a block (lines that are one token, such as base64),
--- split into groups where REAPER started a new group: after a line shorter
--- than `width` (default 128, the width REAPER writes plugin states in) or
--- ending in padding. Plugin states are written as several separately
--- encoded parts this way.
function Node:data_groups(width?: integer): {string}
  width = width or 128
  local groups, current: {string}, {string} = {}, {}
  for _, c in ipairs(self.children) do
    local s = data_text(c)
    if s then
      current[#current + 1] = s
      if #s < width or s:sub(-1) == "=" then
        groups[#groups + 1] = table.concat(current)
        current = {}
      end
    end
  end
  if #current > 0 then
    groups[#groups + 1] = table.concat(current)
  end
  return groups
end

--- All data lines joined.
function Node:data(): string
  return table.concat(self:data_groups())
end

--- Replace the data lines with these base64 groups, each starting on a new
--- line and cut into lines of `width` characters (REAPER uses 128 for
--- plugin states).
function Node:set_data(groups: string | {string}, width?: integer): Node
  local list: {string}
  if groups is string then
    list = {groups}
  else
    list = groups
  end
  width = width or 128
  for i = #self.children, 1, -1 do
    local s = data_text(self.children[i])
    if s and s:match("^[%w+/=]+$") then
      table.remove(self.children, i)
    end
  end
  local at = 1
  for _, text in ipairs(list) do
    for i = 1, #text, width do
      self:add(M.line(text:sub(i, i + width - 1)), at)
      at = at + 1
    end
  end
  return self
end

--- Walk the subtree depth first, calling fn(node, parent) for every node.
function Node:walk(fn: function(node: Node, parent: Node), parent?: Node)
  fn(self, parent)
  for _, c in ipairs(self.children or {}) do
    c:walk(fn, self)
  end
end

-- Parsing ----------------------------------------------------------------------

--- A new node read from a line of text.
local function read_node(content: string, raw: string, block: boolean): Node
  local tokens, quotes = M.tokenize(content)
  local node = setmetatable({tokens = tokens, quotes = quotes, raw = raw} as Node, node_meta)
  if block then
    node.children = {}
  end
  node.sig = signature(node.tokens)
  return node
end

--- Parse text into a document: a node whose children are the top-level
--- nodes (for a project, one `REAPER_PROJECT` block, reachable as
--- `doc.project`). Never fails: what does not fit the format is kept as
--- plain lines.
function M.parse(text: string): Node
  local doc = setmetatable({tokens = {}, children = {}, doc = true} as Node, node_meta)
  local stack: {Node} = {doc}
  local pos, n = 1, #text
  while pos <= n do
    local eol = text:find("\n", pos, true)
    local raw = text:sub(pos, eol or n)
    pos = (eol or n) + 1
    local content = raw:gsub("[\r\n]+$", ""):match("^[ \t]*(.-)[ \t]*$")
    local top = stack[#stack]
    if content:sub(1, 1) == "<" then
      local node = read_node(content:sub(2), raw, true)
      top.children[#top.children + 1] = node
      stack[#stack + 1] = node
    elseif content == ">" and #stack > 1 then
      top.close = raw
      stack[#stack] = nil
    else
      top.children[#top.children + 1] = read_node(content, raw, false)
    end
  end
  -- Blocks left open at the end of the file get no closing line, as read.
  for i = #stack, 2, -1 do
    stack[i].close = stack[i].close or ""
  end
  doc.eol = text:match("\r\n") and "\r\n" or "\n"
  find_project(doc)
  return doc
end

--- Read and parse a file.
function M.read(path: string): Node
  local file, err = io.open(path, "rb")
  if not file then
    error("cannot read " .. path .. ": " .. tostring(err), 2)
  end
  local text = file:read("*a")
  file:close()
  return M.parse(text)
end

-- Writing ----------------------------------------------------------------------

local function emit(node: Node, depth: integer, out: {string}, eol: string)
  local indent = string.rep("  ", depth)
  if node.raw and node.sig == signature(node.tokens) then
    out[#out + 1] = node.raw
  else
    local parts: {string} = {}
    local quotes = node.quotes or {}
    for i, t in ipairs(node.tokens) do
      parts[i] = M.quote(t, quotes[i])
    end
    out[#out + 1] = indent .. (node.children and "<" or "") .. table.concat(parts, " ") .. eol
  end
  if node.children then
    for _, c in ipairs(node.children) do
      emit(c, depth + 1, out, eol)
    end
    out[#out + 1] = node.close or (indent .. ">" .. eol)
  end
end

--- Write a document (or a single node) back to text.
function M.write(node: Node): string
  local out: {string} = {}
  local eol = node.eol or "\n"
  if node.doc then
    for _, c in ipairs(node.children) do
      emit(c, 0, out, eol)
    end
  else
    emit(node, 0, out, eol)
  end
  return table.concat(out)
end

--- Write a document to a file, through a temporary file and a rename.
function M.save(doc: Node, path: string)
  local tmp = path .. ".tmp"
  local file = assert(io.open(tmp, "wb"))
  file:write(M.write(doc))
  file:close()
  assert(os.rename(tmp, path))
end

--- A new, empty document whose lines will end in `eol` (default "\n").
function M.document(eol?: string): Node
  return setmetatable({tokens = {}, children = {}, doc = true, eol = eol or "\n"} as Node, node_meta)
end

return M
