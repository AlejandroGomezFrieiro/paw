-- The binary forms of JUCE plugins (TONE3000 and others), read and written
-- back byte for byte:
--
--   a ValueTree as `ValueTree::writeToStream` writes it: its type, its
--   properties (each a name and a `var`), its children
--   the base64 of `MemoryBlock::toBase64Encoding` ("<size>.<chars>"), which
--   JUCE's LV2 wrapper puts in the plugin's state
--
-- A tree is `{ type = "ChainBlock", props = { { name, raw }, ... },
-- children = { tree, ... } }`. `raw` is the property's value as stored (its
-- kind byte, then the data), so a property that is not changed is written
-- back as it was. A tree read from XML (`plugstate.jucexml`) has the same
-- form: its attributes are string values.
--
-- Paths name the parts of a tree: `/TONE3000State/ChainSnapshot/ChainBlocks/
-- ChainBlock[3]@activeModelId`. The first step is the root. A step is a
-- type (or `*`), with filters: `[2]` the second of those, `[id=gain]` those
-- whose property has the value. `@name` at the end names a property.
local ffi = require("ffi")
local bit = require("bit")
local vst3 = { split = paw.bytes.vst3_split, join = paw.bytes.vst3_join }

local M = {}

-- --- compressed integers: a count of bytes (high bit: negative), then the
-- number, little-endian ----------------------------------------------------

local function read_cint(s, i)
  local n = s:byte(i)
  if not n then error("the data ends early", 0) end
  local neg = n >= 128
  n = n % 128
  if n > 8 then error("not a JUCE number", 0) end
  local v = 0
  for k = n, 1, -1 do
    local b = s:byte(i + k)
    if not b then error("the data ends early", 0) end
    v = v * 256 + b
  end
  return neg and -v or v, i + 1 + n
end

local function cint(v)
  local neg = v < 0
  if neg then v = -v end
  local out = {}
  while v > 0 do
    out[#out + 1] = string.char(v % 256)
    v = math.floor(v / 256)
  end
  return string.char(#out + (neg and 128 or 0)) .. table.concat(out)
end
M.read_cint, M.cint = read_cint, cint

-- --- var ----------------------------------------------------------------------

local KIND = { int = 1, ["true"] = 2, ["false"] = 3, double = 4, string = 5, int64 = 6, array = 7, binary = 8, undefined = 9 }
local KIND_NAME = {}
for name, n in pairs(KIND) do KIND_NAME[n] = name end
KIND_NAME[2], KIND_NAME[3] = "bool", "bool"
M.KIND = KIND

local d1 = ffi.new("double[1]")
local i1 = ffi.new("int32_t[1]")
local l1 = ffi.new("int64_t[1]")

local value

-- The vars of an array's data: a count, then each var after its size.
local function array_of(data)
  local out = {}
  local n, i = read_cint(data, 1)
  for k = 1, n do
    local size
    size, i = read_cint(data, i)
    out[k] = value(data:sub(i, i + size - 1))
    i = i + size
  end
  return out
end

--- The value of a stored var: a number, a boolean, a string, for a
--- binary block `{ binary = <bytes> }`, for an array `{ array = { ... } }`.
function value(raw)
  if not raw or raw == "" then return nil end
  local kind, data = raw:byte(1), raw:sub(2)
  if kind == 1 then ffi.copy(i1, data, 4) return tonumber(i1[0]) end
  if kind == 2 then return true end
  if kind == 3 then return false end
  if kind == 4 then ffi.copy(d1, data, 8) return tonumber(d1[0]) end
  if kind == 5 then return (data:gsub("%z$", "")) end
  if kind == 6 then ffi.copy(l1, data, 8) return tonumber(l1[0]) end
  if kind == 7 then return { array = array_of(data) } end
  if kind == 8 then return { binary = data } end
  return nil
end
M.value = value

--- The kind of a stored var: "int", "bool", "double", "string", "int64",
--- "array", "binary" or "undefined".
function M.kind(raw)
  return raw and raw ~= "" and KIND_NAME[raw:byte(1)] or nil
end

--- A var stored: `kind` is "int", "int64", "double" (numbers without it),
--- "string", "binary" (a string of bytes), or none for what the value is.
--- An array is `{ array = { value, ... } }`.
function M.raw(v, kind)
  local t = type(v)
  if t == "boolean" then return string.char(v and 2 or 3) end
  if kind == "string" then return "\5" .. tostring(v) .. "\0" end
  if t == "number" then
    if kind == "int" then i1[0] = v return "\1" .. ffi.string(i1, 4) end
    if kind == "int64" then l1[0] = v return "\6" .. ffi.string(l1, 8) end
    d1[0] = v
    return "\4" .. ffi.string(d1, 8)
  end
  if t == "table" and v.binary then return "\8" .. v.binary end
  if t == "table" and v.array then
    local out = { cint(#v.array) }
    for _, item in ipairs(v.array) do
      local r = M.raw(item)
      out[#out + 1] = cint(#r) .. r
    end
    return "\7" .. table.concat(out)
  end
  if kind == "binary" then return "\8" .. v end
  return "\5" .. tostring(v) .. "\0"
end

-- --- trees --------------------------------------------------------------------

--- The tree at `i` (from 1) of `s`, and where it ends.
function M.parse(s, i)
  i = i or 1
  local zero = s:find("\0", i, true)
  if not zero then error("not a JUCE tree", 0) end
  local node = { type = s:sub(i, zero - 1), props = {}, children = {} }
  i = zero + 1
  local n
  n, i = read_cint(s, i)
  if n < 0 then error("not a JUCE tree", 0) end
  for k = 1, n do
    local z = s:find("\0", i, true)
    if not z then error("not a JUCE tree", 0) end
    local name = s:sub(i, z - 1)
    local size
    size, i = read_cint(s, z + 1)
    if size < 0 or i + size - 1 > #s then error("the data ends early", 0) end
    node.props[k] = { name, s:sub(i, i + size - 1) }
    i = i + size
  end
  n, i = read_cint(s, i)
  if n < 0 then error("not a JUCE tree", 0) end
  for k = 1, n do node.children[k], i = M.parse(s, i) end
  return node, i
end

--- The tree at `i` of `s` when it is one (its type a name, every count in
--- reason), and where it ends; else nil.
function M.try_parse(s, i)
  i = i or 1
  local zero = s:find("\0", i, true)
  if not zero or zero == i or zero - i > 200 then return nil end
  if not s:sub(i, zero - 1):match("^[%a_][%w_:%.%-]*$") then return nil end
  local ok, node, stop = pcall(M.parse, s, i)
  if ok then return node, stop end
end

local function emit(node, out)
  out[#out + 1] = node.type .. "\0" .. cint(#node.props)
  for _, p in ipairs(node.props) do
    out[#out + 1] = p[1] .. "\0" .. cint(#p[2])
    out[#out + 1] = p[2]
  end
  out[#out + 1] = cint(#node.children)
  for _, c in ipairs(node.children) do emit(c, out) end
end

--- The bytes of a tree.
function M.write(node)
  local out = {}
  emit(node, out)
  return table.concat(out)
end

--- A property's value.
function M.get(node, name)
  for _, p in ipairs(node.props) do
    if p[1] == name then return M.value(p[2]) end
  end
end

--- A property's stored var.
function M.get_raw(node, name)
  for _, p in ipairs(node.props) do
    if p[1] == name then return p[2] end
  end
end

--- Set a property (added at the end when it is not there). Without
--- `kind`, a number keeps the kind the property has (int, int64 or
--- double), and a property of a tree read from XML stays text.
function M.set(node, name, v, kind)
  for _, p in ipairs(node.props) do
    if p[1] == name then
      if not kind and type(v) == "number" then
        local was = M.kind(p[2])
        if (was == "int" or was == "int64") and v == math.floor(v) then kind = was end
      end
      p[2] = M.raw(v, kind or (node.xml and type(v) ~= "boolean" and type(v) ~= "number" and "string" or nil))
      return
    end
  end
  node.props[#node.props + 1] = { name, M.raw(v, kind) }
end

--- Take a property away. True when it was there.
function M.unset(node, name)
  for i, p in ipairs(node.props) do
    if p[1] == name then table.remove(node.props, i) return true end
  end
  return false
end

--- The first child of a type, and its place.
function M.child(node, kind)
  for i, c in ipairs(node.children) do
    if c.type == kind then return c, i end
  end
end

--- A new tree. `props` is `{ { name, value, kind }, ... }`.
function M.tree(kind, props, children)
  local node = { type = kind, props = {}, children = children or {} }
  for _, p in ipairs(props or {}) do M.set(node, p[1], p[2], p[3]) end
  return node
end

--- A deep copy of a tree (what it keeps of its source text too).
function M.copy(node)
  local out = {}
  for k, v in pairs(node) do out[k] = v end
  out.props = {}
  for i, p in ipairs(node.props) do out.props[i] = { p[1], p[2] } end
  out.children = {}
  for i, c in ipairs(node.children) do out.children[i] = M.copy(c) end
  return out
end

-- --- paths ----------------------------------------------------------------------

-- A step: `{ type = "Block" | "*", filters = { { index = 3 } | { name, value } } }`.
local function parse_path(path)
  local steps, prop = {}, nil
  local body, at = path:match("^(.-)@([^/%[%]@]+)$")
  if body then path, prop = body, at end
  path = path:gsub("^/", "")
  if path ~= "" then
    -- Split on `/` outside brackets.
    local depth, start = 0, 1
    local parts = {}
    for i = 1, #path do
      local c = path:sub(i, i)
      if c == "[" then depth = depth + 1 elseif c == "]" then depth = depth - 1
      elseif c == "/" and depth == 0 then parts[#parts + 1] = path:sub(start, i - 1) start = i + 1 end
    end
    parts[#parts + 1] = path:sub(start)
    for _, part in ipairs(parts) do
      local kind = part:match("^([^%[]+)")
      if not kind then error("a step of the path has no type: " .. part, 0) end
      local step = { type = kind, filters = {} }
      for f in part:gmatch("%[(.-)%]") do
        local n = tonumber(f)
        if n then
          step.filters[#step.filters + 1] = { index = n }
        else
          local name, v = f:match("^@?([^=]+)=(.*)$")
          if not name then error("a filter of the path is not `[n]` or `[name=value]`: " .. f, 0) end
          v = v:match('^"(.*)"$') or v:match("^'(.*)'$") or v
          step.filters[#step.filters + 1] = { name = name, value = v }
        end
      end
      steps[#steps + 1] = step
    end
  end
  return steps, prop
end
M.parse_path = parse_path

local function show_plain(v)
  if type(v) == "number" then
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
    return string.format("%.17g", v)
  end
  return tostring(v)
end

local function matches(node, step)
  return step.type == "*" or node.type == step.type
end

local function pick(nodes, filter)
  if filter.index then return { nodes[filter.index] } end
  local out = {}
  for _, n in ipairs(nodes) do
    local v = M.get(n, filter.name)
    if v ~= nil and (show_plain(v) == filter.value or (tonumber(filter.value) and tonumber(filter.value) == v)) then
      out[#out + 1] = n
    end
  end
  return out
end

local function select(candidates, step)
  local found = {}
  for _, c in ipairs(candidates) do
    if matches(c, step) then found[#found + 1] = c end
  end
  for _, f in ipairs(step.filters) do found = pick(found, f) end
  return found
end

--- The nodes a path names (without its `@property`), each as `{ node,
--- parent, index }`, and the property's name.
function M.query(root, path)
  local steps, prop = parse_path(path)
  if #steps == 0 then return { { node = root } }, prop end
  local level = {}
  for _, n in ipairs(select({ root }, steps[1])) do level[#level + 1] = { node = n } end
  for s = 2, #steps do
    local nxt = {}
    for _, at in ipairs(level) do
      local found = select(at.node.children, steps[s])
      for _, n in ipairs(found) do
        for i, c in ipairs(at.node.children) do
          if c == n then nxt[#nxt + 1] = { node = n, parent = at.node, index = i } break end
        end
      end
    end
    level = nxt
  end
  return level, prop
end

--- The first node a path names, or with `@property` the property's value
--- (and its stored var).
function M.find(root, path)
  local found, prop = M.query(root, path)
  local at = found[1]
  if not at then return nil end
  if prop then return M.get(at.node, prop), M.get_raw(at.node, prop) end
  return at.node
end

--- The node a path names; the steps that are not there are made (only
--- steps of a type and `[name=value]` filters can be made).
function M.ensure(root, path)
  local steps = parse_path(path)
  if #steps == 0 then return root end
  if not matches(root, steps[1]) then error("the root is " .. root.type .. ", not " .. steps[1].type, 0) end
  local node = root
  for s = 2, #steps do
    local step = steps[s]
    local found = select(node.children, step)
    if found[1] then
      node = found[1]
    else
      if step.type == "*" then error("cannot make a node of any type (`*`)", 0) end
      local new = M.tree(step.type)
      for _, f in ipairs(step.filters) do
        if f.index then
          if f.index ~= #select(node.children, { type = step.type, filters = {} }) + 1 then
            error("there is no " .. step.type .. "[" .. f.index .. "]", 0)
          end
        else
          M.set(new, f.name, f.value, node.xml and "string" or nil)
        end
      end
      new.xml = node.xml
      node.children[#node.children + 1] = new
      node = new
    end
  end
  return node
end

--- Set the property a path names (`.../Node@name`) in each node it names.
--- With `opts.make`, the nodes that are not there are made. Returns the
--- count of nodes set.
function M.set_path(root, path, v, kind, opts)
  local found, prop = M.query(root, path)
  if not prop then error("the path names no property (`@name` at its end): " .. path, 0) end
  if #found == 0 and opts and opts.make then
    found = { { node = M.ensure(root, (path:gsub("@[^@]*$", ""))) } }
  end
  if #found == 0 then error("nothing at " .. path, 0) end
  for _, at in ipairs(found) do M.set(at.node, prop, v, kind) end
  return #found
end

--- Take away what a path names: nodes, or a property of each. Returns the
--- count taken away.
function M.remove_path(root, path)
  local found, prop = M.query(root, path)
  local n = 0
  if prop then
    for _, at in ipairs(found) do
      if M.unset(at.node, prop) then n = n + 1 end
    end
    return n
  end
  for i = #found, 1, -1 do
    local at = found[i]
    if not at.parent then error("the root cannot be taken away", 0) end
    for k, c in ipairs(at.parent.children) do
      if c == at.node then table.remove(at.parent.children, k) n = n + 1 break end
    end
  end
  return n
end

--- Put a tree into the node a path names, at `index` among its children
--- (the end without it). Returns the tree.
function M.insert_path(root, path, tree, index)
  local parent = M.find(root, path)
  if type(parent) ~= "table" or not parent.children then error("nothing at " .. path, 0) end
  tree.xml = tree.xml or parent.xml
  table.insert(parent.children, index or #parent.children + 1, tree)
  return tree
end

-- --- the tree as a list of paths, differences ------------------------------------

local function simple(v) return type(v) == "string" and v ~= "" and #v <= 64 and not v:find("[%]%[/\"@%c]") end

-- The step of a child in its parent's path: its type, and when the parent
-- has more children of that type, `[id=...]` when its id is unique among
-- them, else `[n]`.
local function step_of(parent, child, index)
  local same, n, ids = 0, 0, {}
  for i, c in ipairs(parent.children) do
    if c.type == child.type then
      same = same + 1
      if i <= index then n = same end
      local id = M.get(c, "id")
      if id ~= nil then ids[show_plain(id)] = (ids[show_plain(id)] or 0) + 1 end
    end
  end
  if same == 1 then return child.type end
  local id = M.get(child, "id")
  if id ~= nil and (type(id) == "number" or simple(id)) and ids[show_plain(id)] == 1 then
    return child.type .. "[id=" .. show_plain(id) .. "]"
  end
  return child.type .. "[" .. n .. "]"
end

--- Every node and property of a tree in order: `{ path, node = tree }` for
--- a node and `{ path, raw }` for a property (path `.../Node@name`).
function M.walk(root)
  local out = {}
  local function go(node, path)
    out[#out + 1] = { path = path, node = node }
    for _, p in ipairs(node.props) do out[#out + 1] = { path = path .. "@" .. p[1], raw = p[2] } end
    for i, c in ipairs(node.children) do go(c, path .. "/" .. step_of(node, c, i)) end
  end
  go(root, "/" .. root.type)
  return out
end

--- A var in words, for a person: text in quotes (cut after `max`
--- characters), numbers, `<binary 1234 bytes>`.
function M.show(raw, max)
  max = max or 60
  local v = M.value(raw)
  local kind = M.kind(raw)
  if v == nil then return "void" end
  if type(v) == "string" then
    local text = #v > max and (v:sub(1, max) .. "…(" .. #v .. " characters)") or v
    return '"' .. text:gsub("\n", "\\n") .. '"'
  end
  if type(v) == "table" and v.binary then return "<binary " .. #v.binary .. " bytes>" end
  if type(v) == "table" and v.array then
    local parts = {}
    for i, item in ipairs(v.array) do
      if i > 8 then parts[#parts + 1] = "…" break end
      parts[#parts + 1] = M.show(M.raw(item), 20)
    end
    return "[" .. table.concat(parts, ", ") .. "]"
  end
  if kind == "int" or kind == "int64" then return show_plain(v) .. " (" .. kind .. ")" end
  return show_plain(v)
end

--- What differs from tree `a` to tree `b`, as `{ op, path, before, after }`:
--- `op` is "set" (a property changed), "add" or "remove" (a property, or a
--- node with all it holds). `before` and `after` are stored vars, or trees.
function M.diff(a, b)
  local wa, wb = M.walk(a), M.walk(b)
  -- `Slot` and `Slot[1]` are the same node: the first of its type, with
  -- or without others beside it.
  local function key(path) return (path:gsub("%[1%]", "")) end
  local ia, ib = {}, {}
  for _, e in ipairs(wa) do ia[key(e.path)] = e end
  for _, e in ipairs(wb) do ib[key(e.path)] = e end
  local out = {}
  local function under(path, gone)
    for g in pairs(gone) do
      if path:sub(1, #g + 1) == g .. "/" or path:sub(1, #g + 1) == g .. "@" then return true end
    end
  end
  local added = {}
  for _, e in ipairs(wb) do
    local was = ia[key(e.path)]
    if not under(e.path, added) then
      if not was then
        out[#out + 1] = { op = "add", path = e.path, after = e.node or e.raw }
        if e.node then added[e.path] = true end
      elseif e.raw and was.raw ~= e.raw then
        out[#out + 1] = { op = "set", path = e.path, before = was.raw, after = e.raw }
      end
    end
  end
  local removed = {}
  for _, e in ipairs(wa) do
    if not ib[key(e.path)] and not under(e.path, removed) then
      out[#out + 1] = { op = "remove", path = e.path, before = e.node or e.raw }
      if e.node then removed[e.path] = true end
    end
  end
  return out
end

--- The changes of `diff` as lines of text.
function M.diff_text(changes, max)
  local lines = {}
  local function show(x)
    if type(x) == "table" then return "<" .. x.type .. ">" end
    return M.show(x, max)
  end
  for _, c in ipairs(changes) do
    if c.op == "set" then
      lines[#lines + 1] = string.format("set    %s: %s → %s", c.path, show(c.before), show(c.after))
    elseif c.op == "add" then
      lines[#lines + 1] = string.format("add    %s = %s", c.path, show(c.after))
    else
      lines[#lines + 1] = string.format("remove %s (was %s)", c.path, show(c.before))
    end
  end
  return lines
end

--- A tree as indented lines of text: each node, then its properties
--- (`@name = value`). `opts.depth` stops lower; `opts.max` cuts long text.
function M.dump(root, opts)
  opts = opts or {}
  local lines = {}
  local function go(node, indent, depth)
    lines[#lines + 1] = indent .. node.type .. (#node.children > 0 and ("  (" .. #node.children .. ")") or "")
    for _, p in ipairs(node.props) do
      lines[#lines + 1] = indent .. "  @" .. p[1] .. " = " .. M.show(p[2], opts.max)
    end
    if opts.depth and depth >= opts.depth then
      if #node.children > 0 then lines[#lines + 1] = indent .. "  …" end
      return
    end
    for _, c in ipairs(node.children) do go(c, indent .. "  ", depth + 1) end
  end
  go(root, "", 1)
  return lines
end

-- --- JUCE's base64 ---------------------------------------------------------------

local CHARS = ".ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+"
local DIGIT = ffi.new("int8_t[256]", -1)
for i = 1, 64 do DIGIT[CHARS:byte(i)] = i - 1 end
local CHAR = ffi.new("uint8_t[64]")
for i = 1, 64 do CHAR[i - 1] = CHARS:byte(i) end

--- Bytes from JUCE's "<size>.<chars>" text.
function M.decode64(text)
  local size, rest = text:match("^(%d+)%.(.*)$")
  if not size then error("not JUCE base64", 0) end
  size = tonumber(size)
  local out = ffi.new("uint8_t[?]", size + 2)
  local src = ffi.cast("const uint8_t*", rest)
  local pos = 0
  for k = 0, #rest - 1 do
    local v = DIGIT[src[k]]
    if v < 0 then error("not JUCE base64", 0) end
    -- Six bits from bit `pos`, least significant first.
    local byte, off = bit.rshift(pos, 3), bit.band(pos, 7)
    if byte < size then
      out[byte] = bit.bor(out[byte], bit.band(bit.lshift(v, off), 0xff))
      if off > 2 and byte + 1 < size then
        out[byte + 1] = bit.bor(out[byte + 1], bit.rshift(v, 8 - off))
      end
    end
    pos = pos + 6
  end
  return ffi.string(out, size)
end

--- JUCE's "<size>.<chars>" text of bytes.
function M.encode64(data)
  local size = #data
  local count = math.floor((size * 8 + 5) / 6)
  local src = ffi.new("uint8_t[?]", size + 2)
  ffi.copy(src, data, size)
  local out = ffi.new("uint8_t[?]", count)
  local pos = 0
  for k = 0, count - 1 do
    local byte, off = bit.rshift(pos, 3), bit.band(pos, 7)
    local v = bit.rshift(src[byte], off)
    if off > 2 then v = bit.bor(v, bit.lshift(src[byte + 1], 8 - off)) end
    out[k] = CHAR[bit.band(v, 63)]
    pos = pos + 6
  end
  return size .. "." .. ffi.string(out, count)
end

--- True when text is JUCE's base64 of as many bytes as it says.
function M.is_base64(text)
  local size, rest = text:match("^(%d+)%.([%w%.%+]*)%z?$")
  if not size then return false end
  return #rest == math.floor((tonumber(size) * 8 + 5) / 6)
end

-- --- a JUCE plugin's state in paw's forms -----------------------------------------
-- paw gives the state of a CLAP plugin as the plugin wrote it; of a VST3
-- plugin as the component's part and the controller's, each after its
-- length; of an LV2 plugin as Turtle text, where JUCE's wrapper puts the
-- plugin's data in base64 under `...:StateString`. `open` finds the
-- plugin's own data in each form, and `close` puts new data back in its
-- place; the rest stays as it was. `plugstate.jucestate` does more: it
-- also takes away the private data JUCE's VST3 wrapper adds after it.

--- The plugin's data in a state (paw's base64), and a function that gives
--- the state with other data in its place.
function M.open(state64, format)
  local raw = paw.bytes.unbase64(state64)
  if format == "lv2" then
    local before, text, after = raw:match('^(.-StateString>%s*")(%d+%.[^"]*)(".*)$')
    if not text then error("the state has no JUCE data", 0) end
    return M.decode64(text), function(data)
      return paw.bytes.base64(before .. M.encode64(data) .. after)
    end
  elseif format == "vst3" then
    local component, controller = vst3.split(raw)
    if not component then error(controller, 0) end
    return component, function(data)
      return paw.bytes.base64(vst3.join(data, controller))
    end
  end
  return raw, function(data) return paw.bytes.base64(data) end
end

return M
