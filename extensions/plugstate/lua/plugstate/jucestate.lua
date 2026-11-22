-- The state of a JUCE plugin, in each form that paw gives it (CLAP, VST3,
-- LV2), as a tree to read and change. The layers around the tree are found
-- by themselves:
--
--   the format: the VST3 component and controller parts and the private
--   data that JUCE's VST3 wrapper puts after the plugin's data; the
--   `...:StateString` of JUCE's LV2 wrapper (JUCE's base64); CLAP as it is
--   `copyXmlToBinary` ("VC2!", a size, the XML), XML text, a binary
--   ValueTree (`ValueTree::writeToStream`), with or without a prefix of
--   four letters ("T3KB"), gzip and zlib data, JUCE's base64 text
--   a header that a plugin's description gives (Surge XT: "sub3", the
--   size of its XML, then the XML)
--
-- What is not changed is written back byte for byte, in each layer.
--
--   local js = require("plugstate.jucestate")
--   local doc = js.open(paw.api.device_state(id), "clap")
--   doc:get("/PluginState@studioReverb")        --> "on"
--   doc:set("/PluginState@studioReverb", "off")
--   paw.api.device_load(id, { state = doc:write() })
local juce = require("plugstate.juce")
local xml = require("plugstate.jucexml")
local bytes = require("plugstate.bytes")
local vst3 = { split = paw.bytes.vst3_split, join = paw.bytes.vst3_join }

local M = { plugins = {} }

--- True when bytes start as zlib data does (a header whose check holds).
local function is_zlib(data)
  local a, b = data:byte(1, 2)
  return a ~= nil
    and b ~= nil
    and a % 16 == 8
    and math.floor(a / 16) <= 7
    and (a * 256 + b) % 31 == 0
    and math.floor(b / 32) % 2 == 0
end

local PRIVATE = "JUCEPrivateData"

local function le64(n) return paw.bytes.le32(n % 4294967296) .. paw.bytes.le32(math.floor(n / 4294967296)) end

local function u64(data, at)
  local lo, hi = paw.bytes.u32(data, at), paw.bytes.u32(data, at + 4)
  if not lo or not hi then return nil end
  return lo + hi * 4294967296
end

local function be32(data, at)
  local a, b, c, d = data:byte(at, at + 3)
  if not d then return nil end
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function be32_bytes(n)
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
end

-- --- the format -------------------------------------------------------------------

--- The form of a state when the caller does not know it: "lv2" (Turtle
--- text), "vst3" (two parts after their lengths) or "clap".
function M.guess_format(raw)
  if raw:find("StateString>", 1, true) and raw:match("^%s*[@<]") then return "lv2" end
  local component, controller = vst3.split(raw)
  if component and vst3.join(component, controller) == raw then return "vst3" end
  return "clap"
end

--- The private data of JUCE's VST3 wrapper at the end of a component's
--- part: the plugin's data, and the trailer (its bytes, and its tree).
function M.split_private(component)
  local n = #component
  if n < 31 or component:sub(n - 14) ~= PRIVATE then return component, nil end
  local size = u64(component, n - 22)
  if not size or size > n - 31 then return component, nil end
  local start = n - 22 - size - 8 -- the 8 zero bytes before the private tree
  if component:sub(start, start + 7) ~= ("\0"):rep(8) then return component, nil end
  local trailer = component:sub(start)
  local tree = size > 0 and juce.try_parse(component, start + 8) or nil
  return component:sub(1, start - 1), trailer, tree
end

--- The trailer JUCE's VST3 wrapper writes after the plugin's data, with
--- the private tree (none: empty, as JUCE 7 and later write it).
function M.private_trailer(tree)
  local body = tree and juce.write(tree) or ""
  return ("\0"):rep(8) .. body .. le64(#body) .. PRIVATE
end

--- The plugin's data in the bytes of a state, and what holds it:
--- `{ format, data, wrap = function(data) -> raw }`, plus for VST3 `trailer`,
--- `private` (its tree) and `controller`, for LV2 the Turtle `text`.
function M.unwrap(raw, format)
  format = format or M.guess_format(raw)
  if format == "vst3" then
    local component, controller = vst3.split(raw)
    if not component then error(controller, 0) end
    -- In a VstW chunk, the private data is inside the chunk: it stays there.
    local data, trailer, private = component, nil, nil
    if component:sub(1, 4) ~= "VstW" then
      data, trailer, private = M.split_private(component)
    end
    return {
      format = format,
      data = data,
      trailer = trailer,
      private = private,
      controller = controller,
      wrap = function(new)
        if new == data then return raw end
        return vst3.join(new .. (trailer or ""), controller)
      end,
    }
  elseif format == "lv2" then
    local before, text, after = raw:match('^(.-StateString>%s*")(%d+%.[^"]*)(".*)$')
    if not text then error("the LV2 state has no JUCE data (no StateString)", 0) end
    local data = juce.decode64(text)
    return {
      format = format,
      data = data,
      text = raw,
      wrap = function(new)
        if new == data then return raw end
        return before .. juce.encode64(new) .. after
      end,
    }
  end
  return { format = format, data = raw, wrap = function(new) return new end }
end

--- The bytes of a state of `format` around a plugin's data. `template`
--- (an unwrapped state of that format, optional) gives what is around it;
--- without one, VST3 gets an empty controller part and LV2 needs
--- `opts.uri`, the plugin's URI.
function M.wrap(data, format, template, opts)
  if template and template.format == format then return template.wrap(data) end
  if format == "vst3" then
    return vst3.join(data .. M.private_trailer(nil), "")
  elseif format == "lv2" then
    local uri = opts and opts.uri
    if not uri then error("an LV2 state needs the plugin's URI", 0) end
    return table.concat({
      "@prefix lv2: <http://lv2plug.in/ns/lv2core#> .\n",
      "@prefix pset: <http://lv2plug.in/ns/ext/presets#> .\n",
      "@prefix state: <http://lv2plug.in/ns/ext/state#> .\n\n",
      "<urn:paw:state>\n\ta pset:Preset ;\n\tlv2:appliesTo <",
      uri,
      "> ;\n",
      "\tstate:state [\n\t\t<",
      uri,
      ':StateString> "',
      juce.encode64(data),
      '"\n\t] .\n',
    })
  end
  return data
end

-- --- the layers in the plugin's data -------------------------------------------------
-- Each layer is `{ name, ... }`; `decode` gives the layers and the tree, and
-- `encode` gives the bytes again from the inside out.

local function printable4(s) return #s == 4 and s:match("^[%w_%-!#%$]+$") ~= nil end

local function xml_layer(text, layers)
  local doc = xml.parse(text)
  layers[#layers + 1] = { name = "xml", doc = doc, text = text }
  return doc.root
end

local decode

-- One layer of `data` from a header that a description gives:
-- `{ magic = "sub3", size = 5, skip = 32 }`: the payload starts after
-- `skip` bytes, its length is the 32-bit number at `size` (from 1).
local function header_layer(data, header, layers)
  if header.magic and data:sub(1, #header.magic) ~= header.magic then return nil end
  local skip = header.skip or #(header.magic or "")
  local size = header.size and paw.bytes.u32(data, header.size) or (#data - skip)
  if not size or skip + size > #data then return nil end
  layers[#layers + 1] = {
    name = "header",
    head = data:sub(1, skip),
    tail = data:sub(skip + size + 1),
    header = header,
    inner = data:sub(skip + 1, skip + size),
  }
  return decode(data:sub(skip + 1, skip + size), layers, nil, 2)
end

function decode(data, layers, desc, depth)
  depth = depth or 1
  if depth > 8 then error("too many layers", 0) end
  if desc and desc.header and depth == 1 then
    local root = header_layer(data, desc.header, layers)
    if root then return root end
  end
  -- JUCE's VST3 wrapper with `JUCE_VST3_CAN_REPLACE_VST2`: "VstW", then
  -- the plugin's data in an FXB bank ("CcnK", "FBCh") or FXP program
  -- ("FPCh") chunk, as a VST2 host keeps it. Big-endian numbers.
  if data:sub(1, 4) == "VstW" and data:sub(17, 20) == "CcnK" then
    local kind = data:sub(25, 28)
    local at = (kind == "FBCh" and 173) or (kind == "FPCh" and 73) or nil
    local size = at and be32(data, at)
    if size and at + 3 + size <= #data then
      local inner = data:sub(at + 4, at + 3 + size)
      layers[#layers + 1] = {
        name = "vstw",
        head = data:sub(1, at - 1),
        tail = data:sub(at + 4 + size),
        inner = inner,
        original = data,
      }
      return decode(inner, layers, nil, depth + 1)
    end
  end
  if data:sub(1, 4) == "VC2!" then
    local size = paw.bytes.u32(data, 5)
    if size and 8 + size <= #data then
      layers[#layers + 1] = { name = "vc2", tail = data:sub(9 + size + 1), nul = data:sub(9 + size, 9 + size) }
      return xml_layer(data:sub(9, 8 + size), layers)
    end
  end
  if data:sub(1, 3) == "\31\139\8" then
    local inner, used = assert(paw.api.inflate(data, "gzip"))
    layers[#layers + 1] = { name = "gzip", inner = inner, original = data:sub(1, used), tail = data:sub(used + 1) }
    return decode(inner, layers, nil, depth + 1)
  end
  if is_zlib(data) then
    local inner, used = paw.api.inflate(data, "zlib")
    if inner then
      layers[#layers + 1] = { name = "zlib", inner = inner, original = data:sub(1, used), tail = data:sub(used + 1) }
      return decode(inner, layers, nil, depth + 1)
    end
  end
  if juce.is_base64(data) then
    local inner = juce.decode64((data:gsub("%z$", "")))
    layers[#layers + 1] = { name = "base64", inner = inner, original = data }
    return decode(inner, layers, nil, depth + 1)
  end
  local bom = data:sub(1, 3) == "\239\187\191" and 4 or 1
  if data:match("^%s*<[%?%a!]", bom) then return xml_layer(data, layers) end
  -- A prefix of four letters before a tree: the description's, or four
  -- that hold a digit ("T3KB"): a tree's own type can start with four
  -- capitals ("PARAMETERS").
  local four = data:sub(1, 4)
  local prefix = desc and desc.prefix
  if (prefix and four == prefix) or (not prefix and printable4(four) and four:find("%d")) then
    local root, stop = juce.try_parse(data, 5)
    if root then
      layers[#layers + 1] = { name = "prefix", prefix = four }
      layers[#layers + 1] = { name = "valuetree", tail = data:sub(stop) }
      return root
    end
  end
  local root, stop = juce.try_parse(data, 1)
  if root then
    layers[#layers + 1] = { name = "valuetree", tail = data:sub(stop) }
    return root
  end
  error("the state holds no JUCE data that plugstate knows (no ValueTree, XML, VC2!, gzip or base64)", 0)
end

-- The bytes of the layers from `i` on, around a tree.
local function encode(layers, i, root)
  local layer = layers[i]
  if layer.name == "valuetree" then return juce.write(root) .. layer.tail end
  if layer.name == "xml" then
    return xml.write({ root = root, before = layer.doc.before, after = layer.doc.after, source = layer.doc.source })
  end
  if layer.name == "prefix" then return layer.prefix .. encode(layers, i + 1, root) end
  if layer.name == "vc2" then
    local text = encode(layers, i + 1, root)
    return "VC2!" .. paw.bytes.le32(#text) .. text .. layer.nul .. layer.tail
  end
  local inner = encode(layers, i + 1, root)
  if layer.name == "header" then
    local head = layer.head
    if layer.header.size then
      local at = layer.header.size
      head = head:sub(1, at - 1) .. paw.bytes.le32(#inner) .. head:sub(at + 4)
    end
    return head .. inner .. layer.tail
  end
  if inner == layer.inner then return layer.original end
  if layer.name == "vstw" then
    -- The sizes: of the chunk, and of the FXB or FXP after "CcnK".
    local head = layer.head
    head = head:sub(1, 20) .. be32_bytes(#head - 24 + 4 + #inner) .. head:sub(25)
    return head .. be32_bytes(#inner) .. inner .. layer.tail
  end
  if layer.name == "gzip" then return assert(paw.api.deflate(inner, "gzip")) .. layer.tail end
  if layer.name == "zlib" then return assert(paw.api.deflate(inner, "zlib")) .. layer.tail end
  if layer.name == "base64" then return juce.encode64(inner) end
  error("unknown layer " .. layer.name, 0)
end

--- The tree in a plugin's data (the bytes `getStateInformation` gives),
--- its layers, and a function that gives the data with a tree.
function M.decode(data, desc)
  local layers = {}
  local root = decode(data, layers, desc)
  return root, layers, function(tree) return encode(layers, 1, tree) end
end

-- --- the document -------------------------------------------------------------------

local Doc = {}
Doc.__index = Doc
M.Doc = Doc

--- A state of a JUCE plugin (paw's base64) as a document: `doc.root` the
--- tree, `doc.layers` what holds it (names in `doc:layer_names()`),
--- `doc.format`, `doc.plugin` (the description, when one fits).
--- `opts.plugin` names a description; `opts.desc` gives one.
function M.open(state64, format, opts)
  opts = opts or {}
  local raw = paw.bytes.unbase64(state64)
  local outer = M.unwrap(raw, format)
  local desc = opts.desc or (opts.plugin and M.plugins[opts.plugin])
  local root, layers, close = M.decode(outer.data, desc)
  local doc = setmetatable({
    format = outer.format,
    outer = outer,
    root = root,
    layers = layers,
    close = close,
    plugin = desc,
    original = juce.write(root),
    raw = raw,
  }, Doc)
  if desc and desc.root and root.type ~= desc.root then
    error("not a state of " .. (desc.title or desc.name) .. " (its root is " .. root.type .. ")", 0)
  end
  return doc
end

--- The plugin's data (the bytes `getStateInformation` gives) now.
function Doc:data()
  if juce.write(self.root) == self.original and not self.changed then return self.outer.data end
  return self.close(self.root)
end

--- The state (paw's base64) now: byte for byte the one opened when
--- nothing changed.
function Doc:write() return paw.bytes.base64(self.outer.wrap(self:data())) end

--- The state for another format of the same plugin: `template` is a state
--- (paw's base64) of that format, for what is around the data; else see
--- `M.wrap`.
function Doc:write_as(format, template64, opts)
  local data = self:data()
  if format == self.format then return paw.bytes.base64(self.outer.wrap(data)) end
  local template = template64 and M.unwrap(paw.bytes.unbase64(template64), format) or nil
  return paw.bytes.base64(M.wrap(data, format, template, opts))
end

function Doc:layer_names()
  local out = { self.format }
  if self.outer.trailer then out[#out + 1] = "juce-private" end
  for _, l in ipairs(self.layers) do
    out[#out + 1] = l.name == "prefix" and ("prefix " .. l.prefix)
      or (l.name == "header" and ("header " .. (l.header.magic or "")) or l.name)
  end
  return out
end

local function named(self, path)
  local paths = self.plugin and self.plugin.paths
  return paths and paths[path] or path
end

--- The value at a path (`@property` at its end) or the node. A name of
--- the description's `paths` stands for its path.
function Doc:get(path) return (juce.find(self.root, named(self, path))) end

--- Every match of a path: `{ node, parent, index }`, and the property.
function Doc:query(path) return juce.query(self.root, named(self, path)) end

--- Set the property at a path. `opts.make` makes the nodes that are not there.
function Doc:set(path, v, kind, opts)
  self.changed = true
  return juce.set_path(self.root, named(self, path), v, kind, opts)
end

function Doc:remove(path)
  self.changed = true
  return juce.remove_path(self.root, named(self, path))
end

--- Put a tree in the node at a path. A tree for an XML state is made with
--- `require("plugstate.jucexml").tree`.
function Doc:insert(path, tree, index)
  self.changed = true
  return juce.insert_path(self.root, named(self, path), tree, index)
end

-- --- AudioProcessorValueTreeState -------------------------------------------------------
-- Its parameters are `PARAM` nodes with `id` and `value`, in one node
-- (often `PARAMETERS`, or the root).

--- The node that holds the `PARAM` nodes (the description's `params` path,
--- else the first node that has one, else the first node with children
--- that have an `id` and a `value`, as HISE's `Control` nodes, else nil).
function Doc:param_holder()
  if self.plugin and self.plugin.params then return juce.ensure(self.root, self.plugin.params) end
  local function find(node, any)
    for _, c in ipairs(node.children) do
      if (any or c.type == "PARAM") and juce.get(c, "id") ~= nil and (not any or juce.get_raw(c, "value") ~= nil) then
        return node
      end
    end
    for _, c in ipairs(node.children) do
      local f = find(c, any)
      if f then return f end
    end
  end
  return find(self.root) or find(self.root, true)
end

local function is_param(c) return juce.get(c, "id") ~= nil and (c.type == "PARAM" or juce.get_raw(c, "value") ~= nil) end

--- The parameters: `{ { id, value }, ... }` in their order (values as
--- numbers when they read as numbers).
function Doc:params()
  local holder = self:param_holder()
  local out = {}
  for _, c in ipairs(holder and holder.children or {}) do
    if is_param(c) then
      local v = juce.get(c, "value")
      out[#out + 1] = { id = juce.get(c, "id"), value = tonumber(v) or v }
    end
  end
  return out
end

--- A parameter's value by its id.
function Doc:param(id)
  for _, p in ipairs(self:params()) do
    if p.id == id then return p.value end
  end
end

--- Set a parameter by its id; one that is not there is added (as
--- `AudioProcessorValueTreeState` reads it, also an id the host does not
--- see as a parameter).
function Doc:set_param(id, v)
  local holder = self:param_holder()
  if not holder then holder = juce.ensure(self.root, "/" .. self.root.type .. "/PARAMETERS") end
  self.changed = true
  for _, c in ipairs(holder.children) do
    if is_param(c) and juce.get(c, "id") == id then
      juce.set(c, "value", v)
      return false
    end
  end
  local node = juce.tree("PARAM", { { "id", id, "string" }, { "value", v } })
  node.xml = holder.xml
  holder.children[#holder.children + 1] = node
  return true
end

--- The tree as lines of text (`juce.dump`).
function Doc:dump(opts) return juce.dump(self.root, opts) end

--- What differs from this document to another (or a tree): `juce.diff`.
function Doc:diff(other) return juce.diff(self.root, other.root or other) end

-- --- descriptions of plugins ---------------------------------------------------------------
-- A description is a few lines:
--
--   jucestate.plugin({
--     name = "surge-xt", title = "Surge XT",
--     ids = { clap = "org.surge-synth-team.surge-xt", vst3 = "Surge XT",
--             lv2 = "https://surge-synthesizer.github.io/lv2/surge-xt" },
--     header = { magic = "sub3", size = 5, skip = 32 },  -- when the plugin has one
--     root = "patch",                                     -- the type of the root
--     paths = { name = "/patch/meta@name" },              -- names for paths
--     params = "/patch/parameters",                       -- the APVTS node, if any
--   })
--
-- `ids.vst3` is the plugin's name (paw knows VST3 plugins by a class id).

--- Add a description of a JUCE plugin.
function M.plugin(desc)
  assert(type(desc.name) == "string", "a description needs a name")
  M.plugins[desc.name] = desc
  return desc
end

--- The description of a device (`paw.api.device_get`), or nil.
function M.plugin_of(d)
  local p = d and d.plugin
  if not p then return nil end
  for _, desc in pairs(M.plugins) do
    local id = desc.ids and desc.ids[p.format]
    if id and (id == p.id or (p.format == "vst3" and id:lower() == (p.name or ""):lower())) then return desc end
  end
end

-- --- presets: a base state and edits -----------------------------------------------------
-- A preset is `{ plugin = name, base = state64 (optional), format =
-- the base's format, edits = { edit, ... } }`. An edit is
-- `{ path, value, kind }` (set; `make = true` makes the nodes), `{ path,
-- remove = true }`, `{ param = id, value }`, or `{ path, insert = tree,
-- index }`.

--- Apply edits to a document.
function M.apply(doc, edits)
  for _, e in ipairs(edits or {}) do
    if e.param then
      doc:set_param(e.param, e.value)
    elseif e.remove then
      doc:remove(e.path or e[1])
    elseif e.insert then
      doc:insert(e.path or e[1], juce.copy(e.insert), e.index)
    else
      doc:set(e.path or e[1], e.value == nil and e[2] or e.value, e.kind or e[3], { make = e.make })
    end
  end
  return doc
end

--- The state (paw's base64) of a preset for a device of `format`: the
--- preset's base (else `current`, the device's state now) with the edits,
--- in the device's format. `current` also gives what is around the data.
function M.generate(preset, format, current, opts)
  local base, base_format = preset.base, preset.format
  if not base then
    base, base_format = current, format
  end
  if not base then error("the preset has no base state, and there is no state of the device", 0) end
  local desc = preset.plugin and M.plugins[preset.plugin] or (opts and opts.desc)
  local doc = M.open(base, base_format, { desc = desc })
  M.apply(doc, preset.edits)
  return doc:write_as(format, current, opts)
end

--- A state of one format as a state of another (`write_as`).
function M.convert(state64, from, to, template64, opts)
  return M.open(state64, from, opts):write_as(to, template64, opts)
end

-- Presets as JSON files: binary values and trees are written as tagged
-- tables, the base as paw's base64.

local function to_json(v)
  if type(v) == "table" and v.binary then return { binary64 = paw.bytes.base64(v.binary) } end
  if type(v) == "table" and v.type and v.props then
    local t = { type = v.type, props = {}, children = {}, xml = v.xml or nil }
    for _, p in ipairs(v.props) do
      t.props[#t.props + 1] = { p[1], paw.bytes.base64(p[2]) }
    end
    for _, c in ipairs(v.children) do
      t.children[#t.children + 1] = to_json(c)
    end
    return { tree = t }
  end
  return v
end

local function from_json(v)
  if type(v) == "table" and v.binary64 then return { binary = paw.bytes.unbase64(v.binary64) } end
  if type(v) == "table" and v.tree then
    local function build(t)
      local node = { type = t.type, props = {}, children = {}, xml = t.xml or nil }
      for _, p in ipairs(t.props or {}) do
        node.props[#node.props + 1] = { p[1], paw.bytes.unbase64(p[2]) }
      end
      for _, c in ipairs(t.children or {}) do
        node.children[#node.children + 1] = build(c)
      end
      return node
    end
    return build(v.tree)
  end
  return v
end

--- Write a preset to a file (JSON). Returns the path.
function M.write_preset(path, preset)
  local edits = {}
  for i, e in ipairs(preset.edits or {}) do
    edits[i] = {
      path = e.path or e[1],
      value = to_json(e.value == nil and e[2] or e.value),
      kind = e.kind or e[3],
      make = e.make,
      remove = e.remove,
      param = e.param,
      insert = e.insert and to_json(e.insert),
      index = e.index,
    }
  end
  local text = paw.json.encode({
    juce_preset = 1,
    plugin = preset.plugin,
    name = preset.name,
    format = preset.format,
    framework = preset.framework,
    base = preset.base,
    edits = edits,
  })
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
  return path
end

--- Read a preset file, or nil and why.
function M.read_preset(path)
  local text, err = bytes.read_file(path)
  if not text then return nil, err end
  local ok, t = pcall(paw.json.decode, text)
  if not ok or type(t) ~= "table" or not t.juce_preset then return nil, path .. ": not a JUCE preset of plugstate" end
  for _, e in ipairs(t.edits or {}) do
    e.value = from_json(e.value)
    if e.insert then e.insert = from_json(e.insert) end
  end
  return t
end

return M
