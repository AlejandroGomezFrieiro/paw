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
--
-- The document is also the document of `plugstate.frameworks`, whose
-- readers give the same interface for the states of other frameworks.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local juce = require("plugstate.juce")
local xml = require("plugstate.jucexml")
local bytes = require("plugstate.bytes")
local type types = require("paw.types")

local api = paw.api
local vst3 = {split = paw.bytes.vst3_split, join = paw.bytes.vst3_join}

local type Tree = juce.Tree
local type Value = juce.Value

local record M
  --- A header of a plugin's own before its data: the data starts after
  --- `skip` bytes (else after `magic`); its length is the 32-bit number at
  --- `size` (from 1), else the rest.
  record Header
    magic: string
    size: integer
    skip: integer
  end

  --- A value of a described plugin that the `juce` adapter shows and
  --- sets: a key, a label, and the name of a path of the description.
  record DescSlot
    key: string
    label: string
    path: string
    what: string
  end

  --- A description of a JUCE plugin: its name, its ids in each format
  --- (`vst3`: the plugin's name), and what is known of its state.
  record Desc
    name: string
    title: string
    ids: {string: string}
    --- A header before the data (Surge XT's "sub3").
    header: Header
    --- The four letters before a ValueTree ("T3KB").
    prefix: string
    --- The type of the root.
    root: string
    --- Names for paths: `doc:get("name")` reads the path of `name`.
    paths: {string: string}
    --- The path of the node of the parameters (an APVTS node).
    params: string
    --- Paths that are not the sound (the state of the window).
    ignore: {string}
    slots: {DescSlot}
  end

  --- The plugin's data in a state, and what is around it: for VST3 the
  --- trailer of JUCE's wrapper (`trailer`, with its tree `private`) and
  --- the controller's part, for LV2 the Turtle `text`. `wrap` gives the
  --- state with other data in its place.
  record Outer
    format: string
    data: string
    trailer: string
    private: Tree
    controller: string
    text: string
    wrap: function(data: string): string
  end

  --- What a state of a format needs besides the data: an LV2 state
  --- without a template names the plugin's URI.
  record WrapOptions
    uri: string
  end

  enum LayerName
    "xml"
    "header"
    "vstw"
    "vc2"
    "gzip"
    "zlib"
    "base64"
    "prefix"
    "valuetree"
  end

  --- A layer around the tree in the plugin's data, with what it needs to
  --- be written again: the bytes before and after (`head`, `tail`), the
  --- inner bytes as read and the whole layer as read (`inner`,
  --- `original`), the XML document, the prefix, the header.
  record Layer
    name: LayerName
    doc: xml.Doc
    text: string
    head: string
    tail: string
    inner: string
    original: string
    nul: string
    prefix: string
    header: Header
  end

  --- A parameter: its id and its value (a number when it reads as one).
  record Param
    id: Value
    value: Value
  end

  --- How `open` reads: `plugin` names a description, `desc` gives one.
  record OpenOptions
    plugin: string
    desc: Desc
  end

  --- A state as a document: `root` the tree, `layers` what holds it
  --- (names in `layer_names()`), `format`, `plugin` (the description, when
  --- one fits), `framework` and `title` (`plugstate.frameworks`).
  record Doc
    format: string
    outer: Outer
    root: Tree
    layers: {Layer}
    --- The plugin's data with a tree in place of the one read.
    close: function(root: Tree): string
    plugin: Desc
    --- The bytes of the tree as read: what changes when the tree changes.
    original: string
    raw: string
    --- Set by each change through the document.
    changed: boolean
    framework: string
    title: string
    notes: {string}
    --- A document of `plugstate.frameworks`: the path of the node of its
    --- parameters, the names of its layers, and the reader's own way to
    --- read and set the parameters.
    params_path: string
    layer_list: {string}
    reader_params: function(self: Doc): {Param}
    reader_set_param: function(self: Doc, id: Value, v: Value): boolean

    data: function(self: Doc): string
    write: function(self: Doc): string
    write_as: function(self: Doc, format: string, template64?: string, opts?: WrapOptions): string
    layer_names: function(self: Doc): {string}
    get: function(self: Doc, path: string): juce.Found
    query: function(self: Doc, path: string): {juce.Match}, string
    set: function(self: Doc, path: string, v: Value, kind?: juce.Kind, opts?: juce.SetOptions): integer
    remove: function(self: Doc, path: string): integer
    insert: function(self: Doc, path: string, tree: Tree, index?: integer): Tree
    param_holder: function(self: Doc): Tree
    params: function(self: Doc): {Param}
    param: function(self: Doc, id: Value): Value
    set_param: function(self: Doc, id: Value, v: Value): boolean
    dump: function(self: Doc, opts?: juce.DumpOptions): {string}
    diff: function(self: Doc, other: Doc): {juce.Change}
  end

  --- An edit of a preset: set the property at `path` (`make` makes the
  --- nodes), take away what `path` names (`remove`), put a tree into the
  --- node at `path` (`insert`, at `index`), or set a parameter (`param`).
  record Edit
    path: string
    value: Value
    kind: juce.Kind
    make: boolean
    remove: boolean
    param: Value
    insert: Tree
    index: integer
  end

  --- A preset: a base state (paw's base64) of `format`, or none (the
  --- device's state), and the edits; `plugin` names a description,
  --- `framework` the framework of `plugstate.frameworks` it is for.
  record Preset
    plugin: string
    name: string
    base: string
    format: string
    framework: string
    edits: {Edit}
  end

  --- How `convert` reads and writes a state.
  record ConvertOptions
    plugin: string
    desc: Desc
    uri: string
  end

  --- How `generate` makes a state: the description, the URI of an LV2
  --- plugin, and for `plugstate.frameworks` the host's parameters and the
  --- framework that the plugin's binary names.
  record GenerateOptions
    desc: Desc
    uri: string
    param_info: {types.ParamInfo}
    hint: string
  end

  plugins: {string: Desc}
end

local type Doc = M.Doc
local type Layer = M.Layer
local type Desc = M.Desc

M.plugins = {}

--- True when bytes start as zlib data does (a header whose check holds).
local function is_zlib(data: string): boolean
  local a, b = data:byte(1, 2)
  return a ~= nil and b ~= nil and a % 16 == 8 and a // 16 <= 7 and (a * 256 + b) % 31 == 0 and (b // 32) % 2 == 0
end

local PRIVATE = "JUCEPrivateData"

local function le64(n: integer): string
  return paw.bytes.le32(n % 4294967296) .. paw.bytes.le32(n // 4294967296)
end

local function u64(data: string, at: integer): integer
  local lo, hi = paw.bytes.u32(data, at), paw.bytes.u32(data, at + 4)
  if not lo or not hi then
    return nil
  end
  return lo + hi * 4294967296
end

local function be32(data: string, at: integer): integer
  local a, b, c, d = data:byte(at, at + 3)
  if not d then
    return nil
  end
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function be32_bytes(n: integer): string
  return string.char((n // 16777216) % 256, (n // 65536) % 256, (n // 256) % 256, n % 256)
end

-- --- the format -------------------------------------------------------------------

--- The form of a state when the caller does not know it: "lv2" (Turtle
--- text), "vst3" (two parts after their lengths) or "clap".
function M.guess_format(raw: string): string
  if raw:find("StateString>", 1, true) and raw:match("^%s*[@<]") then
    return "lv2"
  end
  local component, controller = vst3.split(raw)
  if component and vst3.join(component, controller) == raw then
    return "vst3"
  end
  return "clap"
end

--- The private data of JUCE's VST3 wrapper at the end of a component's
--- part: the plugin's data, and the trailer (its bytes, and its tree).
function M.split_private(component: string): string, string, Tree
  local n = #component
  if n < 31 or component:sub(n - 14) ~= PRIVATE then
    return component, nil
  end
  local size = u64(component, n - 22)
  if not size or size > n - 31 then
    return component, nil
  end
  local start = n - 22 - size - 8 -- the 8 zero bytes before the private tree
  if component:sub(start, start + 7) ~= ("\0"):rep(8) then
    return component, nil
  end
  local trailer = component:sub(start)
  local tree: Tree = size > 0 and juce.try_parse(component, start + 8) or nil
  return component:sub(1, start - 1), trailer, tree
end

--- The trailer JUCE's VST3 wrapper writes after the plugin's data, with
--- the private tree (none: empty, as JUCE 7 and later write it).
function M.private_trailer(tree?: Tree): string
  local body = tree and juce.write(tree) or ""
  return ("\0"):rep(8) .. body .. le64(#body) .. PRIVATE
end

--- The plugin's data in the bytes of a state, and what holds it:
--- `{ format, data, wrap = function(data) -> raw }`, plus for VST3 `trailer`,
--- `private` (its tree) and `controller`, for LV2 the Turtle `text`.
function M.unwrap(raw: string, format?: string): M.Outer
  format = format or M.guess_format(raw)
  if format == "vst3" then
    local component, controller = vst3.split(raw)
    if not component then
      error(controller, 0)
    end
    -- In a VstW chunk, the private data is inside the chunk: it stays there.
    local data, trailer, private = component, nil as string, nil as Tree
    if component:sub(1, 4) ~= "VstW" then
      data, trailer, private = M.split_private(component)
    end
    return {
      format = format,
      data = data,
      trailer = trailer,
      private = private,
      controller = controller,
      wrap = function(new: string): string
        if new == data then
          return raw
        end
        return vst3.join(new .. (trailer or ""), controller)
      end,
    }
  elseif format == "lv2" then
    local before, text, after = raw:match('^(.-StateString>%s*")(%d+%.[^"]*)(".*)$')
    if not text then
      error("the LV2 state has no JUCE data (no StateString)", 0)
    end
    local data = juce.decode64(text)
    return {
      format = format,
      data = data,
      text = raw,
      wrap = function(new: string): string
        if new == data then
          return raw
        end
        return before .. juce.encode64(new) .. after
      end,
    }
  end
  return {
    format = format,
    data = raw,
    wrap = function(new: string): string return new end,
  }
end

--- The bytes of a state of `format` around a plugin's data. `template`
--- (an unwrapped state of that format, optional) gives what is around it;
--- without one, VST3 gets an empty controller part and LV2 needs
--- `opts.uri`, the plugin's URI.
function M.wrap(data: string, format: string, template?: M.Outer, opts?: M.WrapOptions): string
  if template and template.format == format then
    return template.wrap(data)
  end
  if format == "vst3" then
    return vst3.join(data .. M.private_trailer(nil), "")
  elseif format == "lv2" then
    local uri = opts and opts.uri
    if not uri then
      error("an LV2 state needs the plugin's URI", 0)
    end
    return table.concat(
      {
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
      }
    )
  end
  return data
end

-- --- the layers in the plugin's data -------------------------------------------------
-- `decode` gives the layers and the tree, and `encode` gives the bytes
-- again from the inside out.

local function printable4(s: string): boolean
  return #s == 4 and s:match("^[%w_%-!#%$]+$") ~= nil
end

local function xml_layer(text: string, layers: {Layer}): Tree
  local doc = xml.parse(text)
  layers[#layers + 1] = {name = "xml", doc = doc, text = text}
  return doc.root
end

local decode: function(data: string, layers: {Layer}, desc: Desc, depth?: integer): Tree

-- One layer of `data` from a header that a description gives:
-- `{ magic = "sub3", size = 5, skip = 32 }`: the payload starts after
-- `skip` bytes, its length is the 32-bit number at `size` (from 1).
local function header_layer(data: string, header: M.Header, layers: {Layer}): Tree
  if header.magic and data:sub(1, #header.magic) ~= header.magic then
    return nil
  end
  local skip = header.skip or #(header.magic or "")
  local size = header.size and paw.bytes.u32(data, header.size) or (#data - skip)
  if not size or skip + size > #data then
    return nil
  end
  layers[#layers + 1] = {
    name = "header",
    head = data:sub(1, skip),
    tail = data:sub(skip + size + 1),
    header = header,
    inner = data:sub(skip + 1, skip + size),
  }
  return decode(data:sub(skip + 1, skip + size), layers, nil, 2)
end

-- JUCE's VST3 wrapper with `JUCE_VST3_CAN_REPLACE_VST2`: "VstW", then the
-- plugin's data in an FXB bank ("CcnK", "FBCh") or FXP program ("FPCh")
-- chunk, as a VST2 host keeps it. Big-endian numbers. Nil when the data is
-- not one.
local function vstw_layer(data: string, layers: {Layer}, depth: integer): Tree
  if data:sub(1, 4) ~= "VstW" or data:sub(17, 20) ~= "CcnK" then
    return nil
  end
  local kind = data:sub(25, 28)
  local at = (kind == "FBCh" and 173) or (kind == "FPCh" and 73) or nil
  local size = at and be32(data, at)
  if not size or at + 3 + size > #data then
    return nil
  end
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

-- The layers that hold other data (gzip, zlib, JUCE's base64), or nil.
local function packed_layer(data: string, layers: {Layer}, depth: integer): Tree
  if data:sub(1, 3) == "\31\139\8" then
    local inner, used = api.inflate(data, "gzip")
    if not inner then
      error(used, 0)
    end
    local n = used as integer
    layers[#layers + 1] = {name = "gzip", inner = inner, original = data:sub(1, n), tail = data:sub(n + 1)}
    return decode(inner, layers, nil, depth + 1)
  end
  if is_zlib(data) then
    local inner, used = api.inflate(data, "zlib")
    if inner then
      local n = used as integer
      layers[#layers + 1] = {name = "zlib", inner = inner, original = data:sub(1, n), tail = data:sub(n + 1)}
      return decode(inner, layers, nil, depth + 1)
    end
  end
  if juce.is_base64(data) then
    local inner = juce.decode64((data:gsub("%z$", "")))
    layers[#layers + 1] = {name = "base64", inner = inner, original = data}
    return decode(inner, layers, nil, depth + 1)
  end
  return nil
end

-- A ValueTree, after a prefix of four letters or not, or nil. The prefix
-- is the description's, or four letters that hold a digit ("T3KB"): a
-- tree's own type can start with four capitals ("PARAMETERS").
local function valuetree_layer(data: string, layers: {Layer}, desc: Desc): Tree
  local four = data:sub(1, 4)
  local prefix = desc and desc.prefix
  if (prefix and four == prefix) or (not prefix and printable4(four) and four:find("%d")) then
    local root, stop = juce.try_parse(data, 5)
    if root then
      layers[#layers + 1] = {name = "prefix", prefix = four}
      layers[#layers + 1] = {name = "valuetree", tail = data:sub(stop)}
      return root
    end
  end
  local root, stop = juce.try_parse(data, 1)
  if root then
    layers[#layers + 1] = {name = "valuetree", tail = data:sub(stop)}
    return root
  end
  return nil
end

decode = function(data: string, layers: {Layer}, desc: Desc, depth?: integer): Tree
  depth = depth or 1
  if depth > 8 then
    error("too many layers", 0)
  end
  if desc and desc.header and depth == 1 then
    local root = header_layer(data, desc.header, layers)
    if root then
      return root
    end
  end
  local root = vstw_layer(data, layers, depth)
  if root then
    return root
  end
  if data:sub(1, 4) == "VC2!" then
    local size = paw.bytes.u32(data, 5)
    if size and 8 + size <= #data then
      layers[#layers + 1] = {name = "vc2", tail = data:sub(9 + size + 1), nul = data:sub(9 + size, 9 + size)}
      return xml_layer(data:sub(9, 8 + size), layers)
    end
  end
  root = packed_layer(data, layers, depth)
  if root then
    return root
  end
  local bom = data:sub(1, 3) == "\239\187\191" and 4 or 1
  if data:match("^%s*<[%?%a!]", bom) then
    return xml_layer(data, layers)
  end
  root = valuetree_layer(data, layers, desc)
  if root then
    return root
  end
  error("the state holds no JUCE data that plugstate knows (no ValueTree, XML, VC2!, gzip or base64)", 0)
end

-- Packed data again: the bytes as read when the inner bytes did not change.
local function pack(layer: Layer, inner: string): string
  if inner == layer.inner then
    return layer.original
  end
  if layer.name == "vstw" then
    -- The sizes: of the chunk, and of the FXB or FXP after "CcnK".
    local head = layer.head
    head = head:sub(1, 20) .. be32_bytes(#head - 24 + 4 + #inner) .. head:sub(25)
    return head .. be32_bytes(#inner) .. inner .. layer.tail
  elseif layer.name == "gzip" or layer.name == "zlib" then
    local packed, err = api.deflate(inner, layer.name)
    if not packed then
      error(err, 0)
    end
    return packed .. layer.tail
  elseif layer.name == "base64" then
    return juce.encode64(inner)
  end
  error("unknown layer " .. layer.name, 0)
end

-- The bytes of the layers from `i` on, around a tree.
local function encode(layers: {Layer}, i: integer, root: Tree): string
  local layer = layers[i]
  if layer.name == "valuetree" then
    return juce.write(root) .. layer.tail
  elseif layer.name == "xml" then
    return xml.write({root = root, before = layer.doc.before, after = layer.doc.after, source = layer.doc.source})
  elseif layer.name == "prefix" then
    return layer.prefix .. encode(layers, i + 1, root)
  elseif layer.name == "vc2" then
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
  return pack(layer, inner)
end

--- The tree in a plugin's data (the bytes `getStateInformation` gives),
--- its layers, and a function that gives the data with a tree.
function M.decode(data: string, desc?: Desc): Tree, {Layer}, function(tree: Tree): string
  local layers: {Layer} = {}
  local root = decode(data, layers, desc)
  return root, layers, function(tree: Tree): string return encode(layers, 1, tree) end
end

-- --- the document -------------------------------------------------------------------

local Doc_meta: metatable<Doc> = {__index = M.Doc}

--- A state of a JUCE plugin (paw's base64) as a document: `doc.root` the
--- tree, `doc.layers` what holds it (names in `doc:layer_names()`),
--- `doc.format`, `doc.plugin` (the description, when one fits).
--- `opts.plugin` names a description; `opts.desc` gives one.
function M.open(state64: string, format?: string, opts?: M.OpenOptions): Doc
  opts = opts or {}
  local raw = paw.bytes.unbase64(state64)
  local outer = M.unwrap(raw, format)
  local desc = opts.desc or (opts.plugin and M.plugins[opts.plugin])
  local root, layers, close = M.decode(outer.data, desc)
  local doc = setmetatable(
    {
      format = outer.format,
      outer = outer,
      root = root,
      layers = layers,
      close = close,
      plugin = desc,
      original = juce.write(root),
      raw = raw,
    } as Doc,
    Doc_meta
  )
  if desc and desc.root and root.type ~= desc.root then
    error("not a state of " .. (desc.title or desc.name) .. " (its root is " .. root.type .. ")", 0)
  end
  return doc
end

--- The plugin's data (the bytes `getStateInformation` gives) now.
function M.Doc:data(): string
  if juce.write(self.root) == self.original and not self.changed then
    return self.outer.data
  end
  return self.close(self.root)
end

--- The state (paw's base64) now: byte for byte the one opened when
--- nothing changed.
function M.Doc:write(): string
  return paw.bytes.base64(self.outer.wrap(self:data()))
end

--- The state for another format of the same plugin: `template` is a state
--- (paw's base64) of that format, for what is around the data; else see
--- `M.wrap`.
function M.Doc:write_as(format: string, template64?: string, opts?: M.WrapOptions): string
  local data = self:data()
  if format == self.format then
    return paw.bytes.base64(self.outer.wrap(data))
  end
  local template = template64 and M.unwrap(paw.bytes.unbase64(template64), format) or nil
  return paw.bytes.base64(M.wrap(data, format, template, opts))
end

function M.Doc:layer_names(): {string}
  local out = {self.format}
  if self.outer.trailer then
    out[#out + 1] = "juce-private"
  end
  for _, l in ipairs(self.layers) do
    if l.name == "prefix" then
      out[#out + 1] = "prefix " .. l.prefix
    elseif l.name == "header" then
      out[#out + 1] = "header " .. (l.header.magic or "")
    else
      out[#out + 1] = l.name
    end
  end
  return out
end

-- The path that a name of the description's `paths` stands for.
local function named(self: Doc, path: string): string
  local paths = self.plugin and self.plugin.paths
  return paths and paths[path] or path
end

--- The value at a path (`@property` at its end) or the node. A name of
--- the description's `paths` stands for its path.
function M.Doc:get(path: string): juce.Found
  return (juce.find(self.root, named(self, path)))
end

--- Every match of a path: `{ node, parent, index }`, and the property.
function M.Doc:query(path: string): {juce.Match}, string
  return juce.query(self.root, named(self, path))
end

--- Set the property at a path. `opts.make` makes the nodes that are not there.
function M.Doc:set(path: string, v: Value, kind?: juce.Kind, opts?: juce.SetOptions): integer
  self.changed = true
  return juce.set_path(self.root, named(self, path), v, kind, opts)
end

function M.Doc:remove(path: string): integer
  self.changed = true
  return juce.remove_path(self.root, named(self, path))
end

--- Put a tree in the node at a path. A tree for an XML state is made with
--- `require("plugstate.jucexml").tree`.
function M.Doc:insert(path: string, tree: Tree, index?: integer): Tree
  self.changed = true
  return juce.insert_path(self.root, named(self, path), tree, index)
end

-- --- AudioProcessorValueTreeState -------------------------------------------------------
-- Its parameters are `PARAM` nodes with `id` and `value`, in one node
-- (often `PARAMETERS`, or the root).

-- The first node under `node` (or `node` itself) with a child that is a
-- parameter: a `PARAM` node with an `id`, or with `loose`, a node of any
-- type with an `id` and a `value`.
local function holder_under(node: Tree, loose: boolean): Tree
  for _, c in ipairs(node.children) do
    if (loose or c.type == "PARAM") and juce.get(c, "id") ~= nil and (not loose or juce.get_raw(c, "value") ~= nil) then
      return node
    end
  end
  for _, c in ipairs(node.children) do
    local f = holder_under(c, loose)
    if f then
      return f
    end
  end
  return nil
end

--- The node that holds the `PARAM` nodes (the description's `params` path,
--- else the first node that has one, else the first node with children
--- that have an `id` and a `value`, as HISE's `Control` nodes, else nil).
function M.Doc:param_holder(): Tree
  if self.plugin and self.plugin.params then
    return juce.ensure(self.root, self.plugin.params)
  end
  return holder_under(self.root, false) or holder_under(self.root, true)
end

local function is_param(c: Tree): boolean
  return juce.get(c, "id") ~= nil and (c.type == "PARAM" or juce.get_raw(c, "value") ~= nil)
end

--- A value as a number when it reads as one.
local function numeric(v: Value): Value
  if v is string then
    return tonumber(v) or v
  end
  return v
end

--- The parameters: `{ { id, value }, ... }` in their order (values as
--- numbers when they read as numbers).
function M.Doc:params(): {M.Param}
  local holder = self:param_holder()
  local out: {M.Param} = {}
  for _, c in ipairs(holder and holder.children or {}) do
    if is_param(c) then
      out[#out + 1] = {id = juce.get(c, "id"), value = numeric(juce.get(c, "value"))}
    end
  end
  return out
end

--- A parameter's value by its id.
function M.Doc:param(id: Value): Value
  for _, p in ipairs(self:params()) do
    if p.id == id then
      return p.value
    end
  end
end

--- Set a parameter by its id; one that is not there is added (as
--- `AudioProcessorValueTreeState` reads it, also an id the host does not
--- see as a parameter). True when it was added.
function M.Doc:set_param(id: Value, v: Value): boolean
  local holder = self:param_holder()
  if not holder then
    holder = juce.ensure(self.root, "/" .. self.root.type .. "/PARAMETERS")
  end
  self.changed = true
  for _, c in ipairs(holder.children) do
    if is_param(c) and juce.get(c, "id") == id then
      juce.set(c, "value", v)
      return false
    end
  end
  local node = juce.tree("PARAM", {{"id", id, "string"}, {"value", v}})
  node.xml = holder.xml
  holder.children[#holder.children + 1] = node
  return true
end

--- The tree as lines of text (`juce.dump`).
function M.Doc:dump(opts?: juce.DumpOptions): {string}
  return juce.dump(self.root, opts)
end

--- What differs from this document to another: `juce.diff`.
function M.Doc:diff(other: Doc): {juce.Change}
  return juce.diff(self.root, other.root)
end

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
function M.plugin(desc: Desc): Desc
  assert(type(desc.name) == "string", "a description needs a name")
  M.plugins[desc.name] = desc
  return desc
end

--- The description of a device (`paw.api.device_get`), or nil.
function M.plugin_of(d: types.Device): Desc
  local p = d and d.plugin
  if not p then
    return nil
  end
  for _, desc in pairs(M.plugins) do
    local id = desc.ids and desc.ids[p.format]
    if id and (id == p.id or (p.format == "vst3" and id:lower() == (p.name or ""):lower())) then
      return desc
    end
  end
end

-- --- presets: a base state and edits -----------------------------------------------------
-- A preset is `{ plugin = name, base = state64 (optional), format =
-- the base's format, edits = { edit, ... } }`. An edit is
-- `{ path, value, kind }` (set; `make = true` makes the nodes), `{ path,
-- remove = true }`, `{ param = id, value }`, or `{ path, insert = tree,
-- index }`.

--- Apply edits to a document.
function M.apply(doc: Doc, edits?: {M.Edit}): Doc
  for _, e in ipairs(edits or {}) do
    if e.param then
      doc:set_param(e.param, e.value)
    elseif e.remove then
      doc:remove(e.path)
    elseif e.insert then
      doc:insert(e.path, juce.copy(e.insert), e.index)
    else
      doc:set(e.path, e.value, e.kind, {make = e.make})
    end
  end
  return doc
end

--- The state (paw's base64) of a preset for a device of `format`: the
--- preset's base (else `current`, the device's state now) with the edits,
--- in the device's format. `current` also gives what is around the data.
function M.generate(preset: M.Preset, format: string, current: string, opts?: M.GenerateOptions): string
  local base, base_format = preset.base, preset.format
  if not base then
    base, base_format = current, format
  end
  if not base then
    error("the preset has no base state, and there is no state of the device", 0)
  end
  local desc = preset.plugin and M.plugins[preset.plugin] or (opts and opts.desc)
  local doc = M.open(base, base_format, {desc = desc})
  M.apply(doc, preset.edits)
  return doc:write_as(format, current, {uri = opts and opts.uri})
end

--- A state of one format as a state of another (`write_as`). `opts`
--- names the description (`plugin`, `desc`) and the URI of an LV2 plugin.
function M.convert(state64: string, from: string, to: string, template64?: string, opts?: M.ConvertOptions): string
  opts = opts or {}
  return M.open(state64, from, {plugin = opts.plugin, desc = opts.desc}):write_as(to, template64, {uri = opts.uri})
end

-- Presets as JSON files: binary values and trees are written as tagged
-- tables, the base as paw's base64.

--- A tree in a preset file: its properties' stored vars in base64.
local record TreeFile
  type: string
  props: {{string, string}}
  children: {TreeFile}
  xml: boolean
  --- What files before plugstate's Teal port wrote for a child: the tree
  --- in a tag (`{ tree = ... }`).
  tree: TreeFile
end

--- A tagged value in a preset file: a binary block, an array of vars, or
--- a tree.
local record Tagged
  binary64: string
  array: {Value}
  tree: TreeFile
end

--- A value in a preset file.
local type FileValue = number | boolean | string | Tagged

--- An edit in a preset file.
local record EditFile
  path: string
  value: FileValue
  kind: juce.Kind
  make: boolean
  remove: boolean
  param: Value
  insert: Tagged
  index: integer
end

--- A preset file (`.jucepreset`).
local record PresetFile
  juce_preset: integer
  plugin: string
  name: string
  format: string
  framework: string
  base: string
  edits: {EditFile}
end

local function tree_file(t: Tree): TreeFile
  local out: TreeFile = {type = t.type, props = {}, children = {}, xml = t.xml or nil}
  for _, p in ipairs(t.props) do
    out.props[#out.props + 1] = {p[1], paw.bytes.base64(p[2])}
  end
  for _, c in ipairs(t.children) do
    out.children[#out.children + 1] = tree_file(c)
  end
  return out
end

local function tree_from_file(t: TreeFile): Tree
  t = t.tree or t
  local node: Tree = {type = t.type, props = {}, children = {}, xml = t.xml or nil}
  for _, p in ipairs(t.props or {}) do
    node.props[#node.props + 1] = {p[1], paw.bytes.unbase64(p[2])}
  end
  for _, c in ipairs(t.children or {}) do
    node.children[#node.children + 1] = tree_from_file(c)
  end
  return node
end

local function value_file(v: Value): FileValue
  if v is juce.Blob then
    if v.binary then
      return {binary64 = paw.bytes.base64(v.binary)}
    end
    return {array = v.array}
  end
  return v
end

local function value_from_file(v: FileValue): Value
  if v is Tagged then
    if v.binary64 then
      return {binary = paw.bytes.unbase64(v.binary64)}
    end
    return {array = v.array}
  end
  return v
end

--- Write a preset to a file (JSON). Returns the path.
function M.write_preset(path: string, preset: M.Preset): string
  local edits: {EditFile} = {}
  for i, e in ipairs(preset.edits or {}) do
    edits[i] = {
      path = e.path,
      value = value_file(e.value),
      kind = e.kind,
      make = e.make,
      remove = e.remove,
      param = e.param,
      insert = e.insert and {tree = tree_file(e.insert)},
      index = e.index,
    }
  end
  local file: PresetFile = {
    juce_preset = 1,
    plugin = preset.plugin,
    name = preset.name,
    format = preset.format,
    framework = preset.framework,
    base = preset.base,
    edits = edits,
  }
  local f = assert(io.open(path, "wb"))
  f:write(api.json_encode(file))
  f:close()
  return path
end

--- Read a preset file, or nil and why.
function M.read_preset(path: string): M.Preset, string
  local text, err = bytes.read_file(path)
  if not text then
    return nil, err
  end
  local ok, t = pcall(api.json_decode, text) as (boolean, PresetFile)
  if not ok or type(t) ~= "table" or not t.juce_preset then
    return nil, path .. ": not a JUCE preset of plugstate"
  end
  local edits: {M.Edit} = {}
  for i, e in ipairs(t.edits or {}) do
    edits[i] = {
      path = e.path,
      value = value_from_file(e.value),
      kind = e.kind,
      make = e.make,
      remove = e.remove,
      param = e.param,
      insert = e.insert and e.insert.tree and tree_from_file(e.insert.tree),
      index = e.index,
    }
  end
  return {
    plugin = t.plugin,
    name = t.name,
    base = t.base,
    format = t.format,
    framework = t.framework,
    edits = edits,
  }
end

return M
