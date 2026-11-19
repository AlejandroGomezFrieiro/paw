-- The saved state of a plugin of any framework that plugstate knows, as a
-- tree to read and change. Each framework has a reader, which finds its
-- format in the bytes of the state (and, as a hint, in the marker strings
-- of the plugin's binary and in the parameters that the host sees):
--
--   juce      JUCE (ValueTree, XML, `VC2!`, the VST3 and LV2 wrappers):
--             `plugstate.jucestate`
--   dpf       DPF (DISTRHO): its key and value pairs in CLAP and VST3
--   lsp       LSP: its ports and KVT in CLAP ("LSP ") and VST3 ("LSPS")
--   iplug2    iPlug2: its strings, then each parameter as a double
--   json      JSON text: nih-plug (`params`, `fields`), Vital, others
--   lv2       the Turtle text of each LV2 state: ports and state keys
--             (DPF and LSP plugins get the same paths as in CLAP and VST3)
--   binary    each other state: its bytes, and when they look so, the
--             32-bit floats in them
--
-- A document has the interface of `plugstate.jucestate`'s: `doc.root` (a
-- tree as `plugstate.juce` gives it, so paths, dump and diff are the same),
-- `get`, `set`, `query`, `remove`, `insert`, `params`, `param`,
-- `set_param`, `dump`, `diff`, `write`, `write_as`, `layer_names`, and
-- `doc.framework`. When nothing changes, `write` gives the same bytes.
--
--   local fw = require("plugstate.frameworks")
--   local doc = fw.open(paw.api.device_state(id), "clap")
--   doc.framework                       --> "dpf"
--   doc:set("/DPF/Parameters@size", 30)
--   paw.api.device_load(id, { state = doc:write() })
local ffi = require("ffi")
local juce = require("plugstate.juce")
local bytes = require("plugstate.bytes")
local jsonspan = require("plugstate.jsonspan")

local M = { readers = {} }

-- --- numbers ----------------------------------------------------------------------

local f1 = ffi.new("float[1]")
local d1 = ffi.new("double[1]")
local i1 = ffi.new("int32_t[1]")

local function f32(data, at) ffi.copy(f1, data:sub(at, at + 3), 4) return tonumber(f1[0]) end
local function pack_f32(v) f1[0] = v return ffi.string(f1, 4) end
local function f64(data, at) ffi.copy(d1, data:sub(at, at + 7), 8) return tonumber(d1[0]) end
local function pack_f64(v) d1[0] = v return ffi.string(d1, 8) end
local function i32(data, at)
  if at + 3 > #data then return nil end
  ffi.copy(i1, data:sub(at, at + 3), 4)
  return tonumber(i1[0])
end
local function pack_i32(v) i1[0] = v return ffi.string(i1, 4) end
M.f32, M.f64, M.i32 = f32, f64, i32

--- A float that a person or a framework writes: "80", "1.29999995".
local function number_text(v, decimal)
  if v == math.floor(v) and math.abs(v) < 1e15 then
    return decimal and string.format("%d.0", v) or string.format("%d", v)
  end
  return string.format("%.9g", v)
end

--- A plausible value of a parameter: finite, and not a tiny number that
--- misaligned bytes give.
local function plausible(v)
  if v ~= v or v == math.huge or v == -math.huge then return false end
  local a = math.abs(v)
  return a == 0 or (a >= 1e-7 and a <= 1e7)
end

-- A name for a property in a path: no `/`, `@`, brackets or space.
local function safe(name)
  return (tostring(name):gsub("[/@%[%]%s]", "_"))
end

-- --- the format around the plugin's data --------------------------------------------

--- The plugin's data in a state, and how to put new data back: for VST3
--- the component's part (the controller's stays), else the bytes as they are.
function M.outer(raw, format)
  if format == "vst3" then
    local size = paw.bytes.u32(raw, 1)
    if size and 4 + size <= #raw then
      local data, rest = raw:sub(5, 4 + size), raw:sub(5 + size)
      local csize = paw.bytes.u32(rest, 1)
      return {
        format = format, data = data, controller = csize and rest:sub(5, 4 + csize) or "",
        wrap = function(new)
          if new == data then return raw end
          return paw.bytes.le32(#new) .. new .. rest
        end,
      }
    end
  end
  return { format = format, data = raw, wrap = function(new) return new end }
end

--- The bytes of a state of `format` around the plugin's data, with what a
--- `template` state of that format (raw bytes, optional) has around it.
function M.wrap(data, format, template)
  if format == "vst3" then
    local rest = paw.bytes.le32(0)
    if template then
      local size = paw.bytes.u32(template, 1)
      if size and 4 + size <= #template then rest = template:sub(5 + size) end
    end
    return paw.bytes.le32(#data) .. data .. rest
  end
  if format == "lv2" then error("an LV2 state is Turtle text: a state of another format does not go into it", 0) end
  return data
end

-- --- properties that remember their text ------------------------------------------
-- A reader keeps, for each property, the raw var and the text it was read
-- from; a property not changed is written back as that text.

local function remember(node, name, v, kind, text, extra)
  juce.set(node, name, v, kind)
  local raw = juce.get_raw(node, name)
  node.orig = node.orig or {}
  node.orig[name] = { raw = raw, text = text, extra = extra }
end

--- The text of a property: its own when it did not change, else
--- `format(value, orig)`. Nil when the node has no such property.
local function text_of(node, name, format)
  local raw = juce.get_raw(node, name)
  if raw == nil then return nil end
  local o = node.orig and node.orig[name]
  if o and o.raw == raw then return o.text end
  return format(juce.value(raw), o, juce.kind(raw))
end

-- --- the document --------------------------------------------------------------------

local Doc = {}
Doc.__index = Doc
M.Doc = Doc

local function named(self, path)
  local paths = self.plugin and self.plugin.paths
  return paths and paths[path] or path
end

function Doc:get(path) return (juce.find(self.root, named(self, path))) end
function Doc:query(path) return juce.query(self.root, named(self, path)) end
function Doc:set(path, v, kind, opts)
  self.changed = true
  return juce.set_path(self.root, named(self, path), v, kind, opts)
end
function Doc:remove(path)
  self.changed = true
  return juce.remove_path(self.root, named(self, path))
end
function Doc:insert(path, tree, index)
  self.changed = true
  return juce.insert_path(self.root, named(self, path), tree, index)
end
function Doc:dump(opts) return juce.dump(self.root, opts) end
function Doc:diff(other) return juce.diff(self.root, other.root or other) end

--- The node of the parameters.
function Doc:param_holder()
  if self.plugin and self.plugin.params then return juce.ensure(self.root, self.plugin.params) end
  return self.params_path and juce.find(self.root, self.params_path) or nil
end

--- The parameters: `{ { id, value }, ... }` in their order, by the names
--- that the format gives them.
function Doc:params()
  if self.reader_params then return self.reader_params(self) end
  local holder = self:param_holder()
  local out = {}
  for _, p in ipairs(type(holder) == "table" and holder.props or {}) do
    local v = juce.value(p[2])
    out[#out + 1] = { id = p[1], value = tonumber(v) or v }
  end
  return out
end

function Doc:param(id)
  for _, p in ipairs(self:params()) do
    if p.id == id then return p.value end
  end
end

--- Set a parameter by its name. A parameter that is not there is an error.
function Doc:set_param(id, v)
  if self.reader_set_param then return self.reader_set_param(self, id, v) end
  local holder = self:param_holder()
  if type(holder) ~= "table" or juce.get_raw(holder, id) == nil then
    error("no parameter " .. tostring(id) .. " in the state", 0)
  end
  self.changed = true
  juce.set(holder, id, tonumber(v) or v)
  return false
end

--- The plugin's data now: the bytes that were opened when nothing changed.
function Doc:data()
  if juce.write(self.root) == self.original then return self.outer.data end
  return self.close(self.root)
end

function Doc:write() return paw.bytes.base64(self.outer.wrap(self:data())) end

--- The state for another format of the same plugin. Only the formats
--- whose data is the same (CLAP and VST3) take it; `template64` is a state
--- of that format, for what is around the data.
function Doc:write_as(format, template64)
  if format == self.format then return self:write() end
  local template = template64 and paw.bytes.unbase64(template64) or nil
  if self.format == "lv2" then error("an LV2 state is Turtle text: it does not go into a state of " .. format, 0) end
  return paw.bytes.base64(M.wrap(self:data(), format, template))
end

function Doc:layer_names()
  local out = { self.format, self.framework }
  for _, l in ipairs(self.layers or {}) do out[#out + 1] = l end
  return out
end

local function document(reader, outer, made, opts)
  local doc = setmetatable({
    format = outer.format, outer = outer, root = made.root, close = made.close, layers = made.layers,
    framework = made.framework or reader.name, title = made.title or reader.title,
    params_path = made.params, reader_params = made.read_params, reader_set_param = made.set_param,
    plugin = opts and opts.desc, notes = made.notes,
  }, Doc)
  doc.original = juce.write(doc.root)
  return doc
end

-- --- readers ---------------------------------------------------------------------------

--- Add a reader: `{ name, title, detect(data, format, ctx), open(data,
--- format, ctx) }`. `open` gives `{ root, close(root) -> data, params =
--- path of the node of the parameters, layers }`. Readers added later are
--- asked first.
function M.reader(def)
  assert(type(def.name) == "string" and def.detect and def.open, "a reader needs name, detect and open")
  for i, r in ipairs(M.readers) do
    if r.name == def.name then table.remove(M.readers, i) break end
  end
  table.insert(M.readers, 1, def)
  return def
end

function M.reader_of(name)
  for _, r in ipairs(M.readers) do
    if r.name == name then return r end
  end
end

-- --- DPF ---------------------------------------------------------------------------------
-- DistrhoPluginVST3.cpp and DistrhoPluginCLAP.cpp write the same text:
-- `__dpf_program__`, the program; the state keys and values between
-- `__dpf_state_begin__` and `__dpf_state_end__`; the parameters by symbol
-- between `__dpf_parameters_begin__` and `__dpf_parameters_end__`. Each
-- string ends with a zero byte; 0xfe and a zero byte end the state.

local DPF = { program = "__dpf_program__", sb = "__dpf_state_begin__", se = "__dpf_state_end__",
  pb = "__dpf_parameters_begin__", pe = "__dpf_parameters_end__" }

local function dpf_number(v, o)
  if type(v) ~= "number" then return tostring(v) end
  local was = o and o.text
  if was and not was:find("[%.eE]") and v == math.floor(v) then return string.format("%d", v) end
  return number_text(v)
end

M.reader({
  name = "dpf", title = "DPF (DISTRHO Plugin Framework)",
  detect = function(data) return data:sub(1, 6) == "__dpf_" end,
  open = function(data)
    local stop = data:find("\254", 1, true)
    if not stop then error("a DPF state with no end", 0) end
    local words = {}
    for w in (data:sub(1, stop - 1)):gmatch("([^%z]*)%z") do words[#words + 1] = w end
    local tail = data:sub(stop)
    local root = juce.tree("DPF")
    local state, params = juce.tree("State"), juce.tree("Parameters")
    root.children = { state, params }
    local i, section, order = 1, nil, {}
    while i <= #words do
      local w = words[i]
      if w == DPF.sb then section = "s" order[#order + 1] = "s" i = i + 1
      elseif w == DPF.pb then section = "p" order[#order + 1] = "p" i = i + 1
      elseif w == DPF.se or w == DPF.pe then section = nil i = i + 1
      elseif w == DPF.program and not section then
        remember(root, "program", tonumber(words[i + 1]) or words[i + 1], "int", words[i + 1])
        order[#order + 1] = "program"
        i = i + 2
      else
        local v = words[i + 1] or ""
        if section == "p" then
          remember(params, w, tonumber(v) or v, nil, v)
        else
          remember(state, w, v, "string", v)
        end
        i = i + 2
      end
    end
    local function close(r)
      local out = {}
      local st, ps = juce.child(r, "State"), juce.child(r, "Parameters")
      for _, part in ipairs(order) do
        if part == "program" then
          out[#out + 1] = DPF.program
          out[#out + 1] = text_of(r, "program", function(v) return tostring(math.floor(tonumber(v) or 0)) end)
        else
          local node = part == "s" and st or ps
          out[#out + 1] = part == "s" and DPF.sb or DPF.pb
          for _, p in ipairs(node and node.props or {}) do
            out[#out + 1] = p[1]
            out[#out + 1] = text_of(node, p[1], dpf_number)
          end
          out[#out + 1] = part == "s" and DPF.se or DPF.pe
        end
      end
      return table.concat(out, "\0") .. "\0" .. tail
    end
    return { root = root, close = close, params = "/DPF/Parameters" }
  end,
})

-- --- LSP ---------------------------------------------------------------------------------
-- lsp-plugin-fw: CLAP (`wrap/clap/impl/wrapper.h`, `save_state_work`)
-- writes "LSP " and a version (32 bits), VST3 (`wrap/vst3/impl/wrapper.h`,
-- `save_state`) "LSPS" and a version (16 bits). Then each port: its id (a
-- varint length, the bytes), a type ('f' float32, 's' a string), the
-- value; `!preset_settings` or `!preset_state` (a varint size, the
-- bytes); the KVT entries (names that start with `/`): a flags byte, a type
-- (`i u I U f F s B`) and the value.

local function varint(data, at)
  local v, shift = 0, 0
  while true do
    local b = data:byte(at)
    if not b then return nil end
    v = v + (b % 128) * 2 ^ shift
    at = at + 1
    if b < 128 then return v, at end
    shift = shift + 7
  end
end

local function pack_varint(v)
  local out = {}
  repeat
    local b = v % 128
    v = math.floor(v / 128)
    out[#out + 1] = string.char(v > 0 and b + 128 or b)
  until v == 0
  return table.concat(out)
end

local function lsp_string(data, at)
  local len, from = varint(data, at)
  if not len or from + len - 1 > #data then return nil end
  return data:sub(from, from + len - 1), from + len
end

local function pack_lsp_string(s) return pack_varint(#s) .. s end

-- The value of a type at `at`: the value, its kind in the tree, its end.
local function lsp_value(data, t, at)
  if t == "f" then return f32(data, at), nil, at + 4 end
  if t == "F" then return f64(data, at), nil, at + 8 end
  if t == "i" then return i32(data, at), "int", at + 4 end
  if t == "u" then return paw.bytes.u32(data, at), "int64", at + 4 end
  if t == "I" or t == "U" then return { binary = data:sub(at, at + 7) }, nil, at + 8 end
  if t == "s" then
    local s, stop = lsp_string(data, at)
    return s, "string", stop
  end
  if t == "B" then
    local size = paw.bytes.u32(data, at)
    local ctype, from = lsp_string(data, at + 4)
    if not size or not from then return nil end
    return { binary = data:sub(from, from + size - 1) }, nil, from + size, ctype
  end
end

local function pack_lsp_value(t, v, o)
  local n = tonumber(v) or (v == true and 1) or 0
  if t == "f" then return pack_f32(n) end
  if t == "F" then return pack_f64(n) end
  if t == "i" then return pack_i32(n) end
  if t == "u" then return paw.bytes.le32(n) end
  if t == "s" then return pack_lsp_string(tostring(v)) end
  if t == "B" then
    local data = type(v) == "table" and v.binary or tostring(v)
    return paw.bytes.le32(#data) .. pack_lsp_string(o and o.extra and o.extra.ctype or "") .. data
  end
  if type(v) == "table" and v.binary then return v.binary end
  error("LSP: cannot write a value of type " .. t, 0)
end

M.reader({
  name = "lsp", title = "LSP (lsp-plugin-fw)",
  detect = function(data) return data:sub(1, 4) == "LSP " or data:sub(1, 4) == "LSPS" end,
  open = function(data)
    local head = data:sub(1, 4) == "LSPS" and 6 or 8
    local root = juce.tree("LSP")
    local params, state = juce.tree("Parameters"), juce.tree("State")
    root.children = { params, state }
    remember(root, "version", data:sub(1, 4) == "LSPS" and (data:byte(5) + data:byte(6) * 256) or paw.bytes.u32(data, 5), "int", data:sub(5, head))
    local records, at = {}, head + 1
    while at <= #data do
      local name, from = lsp_string(data, at)
      if not name or name == "" then break end
      local rec = { name = name }
      if name:sub(1, 1) == "!" then
        local size, b = varint(data, from)
        if not size then break end
        rec.node, rec.prop, rec.kind = state, name, "settings"
        remember(state, name, { binary = data:sub(b, b + size - 1) }, nil, data:sub(from, b + size - 1))
        at = b + size
      else
        local flags
        if name:sub(1, 1) == "/" then flags, from = data:byte(from), from + 1 end
        local t = data:sub(from, from)
        local v, kind, stop, ctype = lsp_value(data, t, from + 1)
        if v == nil then break end
        local node = flags and state or params
        local prop = flags and safe(name:sub(2)) or safe(name)
        rec.node, rec.prop, rec.type, rec.flags = node, prop, t, flags
        remember(node, prop, v, kind, data:sub(from, stop - 1), { ctype = ctype })
        at = stop
      end
      records[#records + 1] = rec
    end
    local tail = data:sub(at)
    local function close(r)
      local out = { data:sub(1, head) }
      for _, rec in ipairs(records) do
        out[#out + 1] = pack_lsp_string(rec.name)
        if rec.flags then out[#out + 1] = string.char(rec.flags) end
        out[#out + 1] = text_of(rec.node, rec.prop, function(v, o)
          if rec.kind == "settings" then
            local b = type(v) == "table" and v.binary or ""
            return pack_varint(#b) .. b
          end
          return rec.type .. pack_lsp_value(rec.type, v, o)
        end) or error("LSP: the record " .. rec.name .. " cannot be taken away", 0)
      end
      out[#out + 1] = tail
      return table.concat(out)
    end
    return { root = root, close = close, params = "/LSP/Parameters" }
  end,
})

-- --- iPlug2 ------------------------------------------------------------------------------
-- IPlugPluginBase.cpp `SerializeParams` puts each parameter's value as a
-- double, in the order of the parameters. A plugin that overrides
-- `SerializeState` often puts strings first (`IByteChunk::PutStr`: a 32-bit
-- length, the bytes), then the parameters, then its own data.
-- IPlugVST3_Common.h puts a 32-bit bypass flag after the chunk in VST3;
-- IPlugCLAP.cpp writes the chunk alone. The parameters are found with the
-- count of parameters the host sees (ids 0 to n-1).

--- The count of the plugin's own parameters in `param_info`: ids 0, 1, 2...
local function counted(info)
  local ids = {}
  for _, p in ipairs(info or {}) do
    local n = tonumber(p.id)
    if n then ids[n] = p end
  end
  local list, n = {}, 0
  while ids[n] do list[#list + 1] = ids[n] n = n + 1 end
  return list
end
M.counted = counted

local function leading_strings(data, limit)
  local out, at = {}, 1
  while at + 3 <= limit and #out < 16 do
    local len = i32(data, at)
    if not len or len < 0 or len > 65536 or at + 3 + len > limit then break end
    local s = data:sub(at + 4, at + 3 + len)
    if s:find("[%z\1-\8\14-\31]") then break end
    out[#out + 1] = { text = s, at = at }
    at = at + 4 + len
  end
  return out
end

M.reader({
  name = "iplug2", title = "iPlug2",
  detect = function(data, format, ctx)
    if ctx.hint ~= "iplug2" and not data:match("^....###[^%z]+###") then return false end
    return #data >= 8
  end,
  open = function(data, format, ctx)
    local list = counted(ctx.param_info)
    local n = #list
    local tail = format == "vst3" and 4 or 0
    local limit = #data - tail
    local strings = leading_strings(data, limit)
    -- Where the parameters start: after some of the strings; the place
    -- where most of the doubles are plausible.
    local start, best = nil, -1
    if n > 0 then
      for k = 0, #strings do
        local at = k == 0 and 1 or (strings[k].at + 4 + #strings[k].text)
        if at + 8 * n - 1 <= limit then
          local score = 0
          for j = 0, n - 1 do
            if plausible(f64(data, at + 8 * j)) then score = score + 1 end
          end
          if score > best or (score == best and score == n) then start, best = at, score end
        end
      end
    end
    local root = juce.tree("IPlug")
    local chunk, params = juce.tree("Chunk"), juce.tree("Parameters")
    root.children = { chunk, params }
    local used = 0
    local first = start or (#strings > 0 and strings[#strings].at + 4 + #strings[#strings].text) or 1
    for k, s in ipairs(strings) do
      if s.at < first then
        used = k
        remember(chunk, "string" .. k, s.text, "string", data:sub(s.at, s.at + 3 + #s.text))
      end
    end
    local names = {}
    if start then
      for j, p in ipairs(list) do
        local name = safe(p.key or p.name or ("p" .. (j - 1)))
        names[j] = name
        remember(params, name, f64(data, start + 8 * (j - 1)), nil, data:sub(start + 8 * (j - 1), start + 8 * j - 1))
      end
    end
    local rest_at = start and (start + 8 * n) or first
    remember(chunk, "data", { binary = data:sub(rest_at, limit) }, nil, data:sub(rest_at, limit))
    if tail > 0 then remember(root, "bypass", i32(data, limit + 1) or 0, "int", data:sub(limit + 1)) end
    local function close(r)
      local ch, ps = juce.child(r, "Chunk"), juce.child(r, "Parameters")
      local out = {}
      for k = 1, used do
        out[#out + 1] = text_of(ch, "string" .. k, function(v) return pack_i32(#tostring(v)) .. tostring(v) end)
      end
      for _, name in ipairs(names) do
        out[#out + 1] = text_of(ps, name, function(v) return pack_f64(tonumber(v) or 0) end)
      end
      out[#out + 1] = text_of(ch, "data", function(v) return type(v) == "table" and v.binary or tostring(v) end)
      if tail > 0 then out[#out + 1] = text_of(r, "bypass", function(v) return pack_i32(tonumber(v) or 0) end) end
      return table.concat(out)
    end
    local notes = not start and { "the parameters were not found: the host gave no list of them" } or nil
    return { root = root, close = close, params = "/IPlug/Parameters", notes = notes }
  end,
})

-- --- Dplug ------------------------------------------------------------------------------
-- dplug/client/preset.d, `writeStateChunk`: the magic 0x0B20BA92 (big
-- endian), the major and minor versions of the format, the plugin's
-- version, the current preset, the count of parameters, each parameter
-- normalized as a float; from major version 1, the size of the plugin's
-- own data (`saveState`) and the data. The names come from the host's
-- list of parameters, in their order.

M.reader({
  name = "dplug", title = "Dplug",
  detect = function(data) return data:sub(1, 4) == "\11\32\186\146" and #data >= 24 end,
  open = function(data, _, ctx)
    local list = counted(ctx.param_info)
    local root = juce.tree("Dplug")
    local params, state = juce.tree("Parameters"), juce.tree("State")
    root.children = { params, state }
    local major = i32(data, 5)
    remember(root, "major", major, "int", data:sub(5, 8))
    remember(root, "minor", i32(data, 9), "int", data:sub(9, 12))
    remember(root, "version", i32(data, 13), "int", data:sub(13, 16))
    remember(root, "preset", i32(data, 17), "int", data:sub(17, 20))
    local n = i32(data, 21)
    if not n or n < 0 or 24 + 4 * n > #data then error("Dplug: the count of parameters does not fit", 0) end
    local names = {}
    for j = 1, n do
      local name = list[j] and safe(list[j].key or list[j].name) or ("p" .. (j - 1))
      names[j] = name
      local at = 25 + 4 * (j - 1)
      remember(params, name, f32(data, at), nil, data:sub(at, at + 3))
    end
    local at = 25 + 4 * n
    local extra = ""
    if major and major >= 1 and at + 3 <= #data then
      local size = i32(data, at) or 0
      remember(state, "data", { binary = data:sub(at + 4, at + 3 + size) }, nil, data:sub(at + 4, at + 3 + size))
      extra = data:sub(at + 4 + size)
    else
      extra = data:sub(at)
    end
    local function close(r)
      -- The header stays; the current preset can change.
      local out = { data:sub(1, 16) .. text_of(r, "preset", function(v) return pack_i32(tonumber(v) or 0) end) .. data:sub(21, 24) }
      local ps, st = juce.child(r, "Parameters"), juce.child(r, "State")
      for _, name in ipairs(names) do
        out[#out + 1] = text_of(ps, name, function(v) return pack_f32(tonumber(v) or 0) end)
      end
      local own = st and juce.get(st, "data")
      if own ~= nil then
        local b = type(own) == "table" and own.binary or tostring(own)
        out[#out + 1] = pack_i32(#b) .. b
      end
      out[#out + 1] = extra
      return table.concat(out)
    end
    return { root = root, close = close, params = "/Dplug/Parameters" }
  end,
})

-- --- JSON --------------------------------------------------------------------------------
-- An object is a node, its numbers, strings and booleans are properties,
-- its objects and arrays are children (an array's items are `item` nodes).
-- Only values change: a value that is set is written in its place.

local function json_tree(text, jnode, kind_name, spans)
  local node = juce.tree(kind_name)
  local function scalar(target, name, item)
    local v = jsonspan.value(text, item)
    local t = text:sub(item.s, item.e)
    if v == nil or type(v) == "userdata" then
      remember(target, name, "null", "string", t)
    elseif type(v) == "number" then
      local whole = not t:find("[%.eE]") and math.abs(v) < 2 ^ 31
      remember(target, name, v, whole and "int" or nil, t)
    elseif type(v) == "boolean" then
      remember(target, name, v, nil, t)
    else
      remember(target, name, v, "string", t)
    end
    spans[#spans + 1] = { node = target, name = name, span = item }
  end
  if jnode.kind == "object" then
    for _, key in ipairs(jnode.keys) do
      local f = jnode.fields[key]
      if f.kind == "object" or f.kind == "array" then
        local child = json_tree(text, f, safe(key), spans)
        if safe(key) ~= key then juce.set(child, "key", key, "string") end
        node.children[#node.children + 1] = child
      else
        scalar(node, safe(key), f)
      end
    end
  elseif jnode.kind == "array" then
    for _, item in ipairs(jnode.items) do
      if item.kind == "object" or item.kind == "array" then
        node.children[#node.children + 1] = json_tree(text, item, "item", spans)
      else
        local holder = juce.tree("item")
        scalar(holder, "value", item)
        node.children[#node.children + 1] = holder
      end
    end
  end
  return node
end

local function json_text(v, o, kind)
  if type(v) == "number" then
    if kind == "int" then return string.format("%d", v) end
    if o and o.text and not o.text:find("[%.eE]") and v == math.floor(v) then return string.format("%d", v) end
    return number_text(v, true)
  end
  if v == "null" and o and o.text == "null" then return "null" end
  return paw.json.encode(v)
end

local function nih_value(node)
  -- nih-plug's `ParamValue`: `{"f32": 0.5}`, or the value itself.
  if #node.props == 1 then
    local v = juce.value(node.props[1][2])
    return tonumber(v) or v, node.props[1][1]
  end
end

M.reader({
  name = "json", title = "JSON",
  detect = function(data) return data:match("^%s*[{%[]") ~= nil and data:match("[}%]]%s*%z?$") ~= nil end,
  open = function(data)
    local stop = #data
    local trailing = ""
    if data:sub(-1) == "\0" then stop, trailing = #data - 1, "\0" end
    local text = data:sub(1, stop)
    local jroot = jsonspan.parse(text)
    local spans = {}
    local root = json_tree(text, jroot, "state", spans)
    local framework, title, params = "json", "JSON", nil
    local read_params, set_param
    if jroot.kind == "object" and jroot.fields.params and jroot.fields.fields then
      framework, title, params = "nih-plug", "nih-plug (PluginState as JSON)", "/state/params"
      read_params = function(doc)
        local holder = juce.find(doc.root, "/state/params")
        local out = {}
        if type(holder) ~= "table" then return out end
        for _, p in ipairs(holder.props) do
          local v = juce.value(p[2])
          out[#out + 1] = { id = p[1], value = tonumber(v) or v }
        end
        for _, c in ipairs(holder.children) do
          out[#out + 1] = { id = c.type, value = (nih_value(c)) }
        end
        return out
      end
      set_param = function(doc, id, v)
        local holder = juce.find(doc.root, "/state/params")
        local c = type(holder) == "table" and juce.child(holder, id)
        if c and #c.props == 1 then
          doc.changed = true
          juce.set(c, c.props[1][1], tonumber(v) or v)
          return false
        end
        if type(holder) == "table" and juce.get_raw(holder, id) ~= nil then
          doc.changed = true
          juce.set(holder, id, tonumber(v) or v)
          return false
        end
        error("no parameter " .. tostring(id) .. " in the state", 0)
      end
    elseif jroot.kind == "object" and (jroot.fields.synth_version or (jroot.fields.settings and jroot.fields.author)) then
      framework, title, params = "vital", "Vital (JSON)", "/state/settings"
    end
    local known = {}
    for _, s in ipairs(spans) do
      known[s.node] = known[s.node] or {}
      known[s.node][s.name] = true
    end
    local function close(r)
      -- What is new in the tree has no place in the text.
      local function walk(n)
        for _, p in ipairs(n.props) do
          if not (known[n] and known[n][p[1]]) and p[1] ~= "key" then
            error("JSON: only values can change, not the keys (" .. n.type .. "@" .. p[1] .. ")", 0)
          end
        end
        for _, c in ipairs(n.children) do walk(c) end
      end
      walk(r)
      local edits = {}
      for _, s in ipairs(spans) do
        local t = text_of(s.node, s.name, json_text)
        if t == nil then error("JSON: a value cannot be taken away (" .. s.name .. ")", 0) end
        if t ~= s.node.orig[s.name].text then edits[#edits + 1] = { s.span, t } end
      end
      return jsonspan.edit(text, edits) .. trailing
    end
    return { root = root, close = close, params = params, framework = framework, title = title,
      read_params = read_params, set_param = set_param }
  end,
})

-- --- LV2: the Turtle text of the state ------------------------------------------------
-- paw keeps an LV2 state as `lilv_state_to_string` writes it: the ports
-- (`lv2:symbol`, `pset:value`) and the plugin's own keys under
-- `state:state`. A port is a parameter; a key is a property of `State`,
-- named by the end of its URI. Each value that changes is written in its
-- place in the text.

local function turtle_unescape(s)
  return (s:gsub("\\(.)", { t = "\t", n = "\n", r = "\r", ['"'] = '"', ["\\"] = "\\", ["'"] = "'" }))
end

local function turtle_string(s)
  if s:find("\n", 1, true) then
    return '"""' .. s:gsub("\\", "\\\\"):gsub('"""', '\\"\\"\\"') .. '"""'
  end
  return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\t", "\\t"):gsub("\r", "\\r") .. '"'
end

local function percent_decode(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end
local function percent_encode(s) return (s:gsub("[^%w%-%._~/:]", function(c) return string.format("%%%02X", c:byte()) end)) end

-- The end of the Turtle value that starts at `i`: the value's last byte.
local function value_end(t, i)
  local c = t:sub(i, i)
  if t:sub(i, i + 2) == '"""' then
    local j = i + 3
    while true do
      local k = t:find('"""', j, true)
      if not k then error("an unfinished string in the LV2 state", 0) end
      local slashes = 0
      while t:sub(k - 1 - slashes, k - 1 - slashes) == "\\" do slashes = slashes + 1 end
      if slashes % 2 == 0 then
        local e = k + 2
        while t:sub(e + 1, e + 1) == '"' do e = e + 1 end
        return e
      end
      j = k + 1
    end
  elseif c == '"' then
    local j = i + 1
    while true do
      local k = t:find('["\\]', j)
      if not k then error("an unfinished string in the LV2 state", 0) end
      if t:sub(k, k) == "\\" then j = k + 2 else return k end
    end
  elseif c == "<" then
    return t:find(">", i, true) or error("an unfinished URI in the LV2 state", 0)
  elseif c == "[" or c == "(" then
    local close = c == "[" and "]" or ")"
    local depth, j = 0, i
    while j <= #t do
      local d = t:sub(j, j)
      if d == '"' then j = value_end(t, j)
      elseif d == c then depth = depth + 1
      elseif d == close then
        depth = depth - 1
        if depth == 0 then return j end
      end
      j = j + 1
    end
    error("an unfinished block in the LV2 state", 0)
  end
  return (t:find("[%s;,%]]", i) or #t + 1) - 1
end

--- The parts of a Turtle value: kind ("string", "typed", "uri", "number",
--- "raw"), the value, the type of a typed literal.
local function turtle_value(t, s, e)
  local text = t:sub(s, e)
  local long = text:match('^"""(.*)"""(.*)$')
  local body, suffix
  if long then
    body, suffix = text:match('^"""(.-)"""([^"]*)$')
  elseif text:sub(1, 1) == '"' then
    local close = value_end(t, s)
    body, suffix = t:sub(s + 1, close - 1), t:sub(close + 1, e)
  end
  if body then
    body = turtle_unescape(body)
    local typ = suffix and suffix:match("^%^%^(.+)$")
    if typ and (typ:find("float") or typ:find("double") or typ:find("decimal")) then
      return "typed", tonumber(body) or body, typ, nil
    end
    if typ and (typ:find("int") or typ:find("long")) then return "typed", tonumber(body) or body, typ, "int" end
    if typ == "xsd:boolean" or (typ and typ:find("boolean")) then return "typed", body == "true", typ end
    if typ then return "typed", body, typ, "string" end
    return "string", body, suffix ~= "" and suffix or nil, "string"
  end
  if text:sub(1, 1) == "<" then
    local uri = text:sub(2, -2)
    if uri:sub(1, 7) == "file://" then return "uri", percent_decode(uri:sub(8)), "file", "string" end
    return "uri", uri, nil, "string"
  end
  if tonumber(text) then return "number", tonumber(text), nil, nil end
  return "raw", text, nil, "string"
end

local function turtle_text(v, o)
  local x = o and o.extra or {}
  if x.kind == "typed" then
    local body = type(v) == "boolean" and tostring(v) or (type(v) == "number" and (x.int and string.format("%d", v) or number_text(v, true)) or tostring(v))
    return turtle_string(body) .. "^^" .. x.type
  elseif x.kind == "uri" then
    return x.type == "file" and ("<file://" .. percent_encode(tostring(v)) .. ">") or ("<" .. tostring(v) .. ">")
  elseif x.kind == "number" or type(v) == "number" then
    return number_text(tonumber(v) or 0, true)
  elseif x.kind == "raw" then
    return tostring(v)
  end
  return turtle_string(tostring(v)) .. (x.type or "")
end

-- A short name for a key's URI: what is after its last `#`, `/` or `:`.
local function key_name(uri, taken)
  local name = safe(uri:match("[#/:]([^#/:]+)$") or uri)
  if taken[name] then name = safe(uri:match("[/:]([^/:]+)$") or uri) end
  local base, n = name, 2
  while taken[name] do name, n = base .. n, n + 1 end
  taken[name] = true
  return name
end

M.reader({
  name = "lv2", title = "LV2 (ports and state keys)",
  detect = function(data, format) return format == "lv2" and data:find("lv2:appliesTo", 1, true) ~= nil end,
  open = function(data, _, ctx)
    local t = data
    local uri = t:match("lv2:appliesTo%s*<([^>]*)>") or ""
    local spans = {}
    local ports, state = juce.tree("Parameters"), juce.tree("State")
    for sym, s, e in t:gmatch('lv2:symbol%s+"([^"]*)"%s*;%s*pset:value%s+()[^%s%]]+()') do
      local v = tonumber(t:sub(s, e - 1))
      remember(ports, safe(sym), v, nil, t:sub(s, e - 1), { kind = "number" })
      spans[#spans + 1] = { node = ports, name = safe(sym), s = s, e = e - 1 }
    end
    local block = t:find("state:state%s*%[")
    local dpf, taken = false, {}
    if block then
      local i = t:find("[", block, true) + 1
      while true do
        i = t:find("%S", i)
        if not i or t:sub(i, i) == "]" then break end
        if t:sub(i, i) ~= "<" then error("the LV2 state has a key that is not a URI", 0) end
        local ke = t:find(">", i, true)
        local key = t:sub(i + 1, ke - 1)
        local vs = t:find("%S", ke + 1)
        local ve = value_end(t, vs)
        if t:sub(vs, vs) == '"' and t:sub(ve + 1, ve + 2) == "^^" then ve = value_end(t, ve + 3)
        elseif t:sub(vs, vs) == '"' and t:sub(ve + 1, ve + 1) == "@" then ve = value_end(t, ve + 1) end
        local kind, v, typ, vkind = turtle_value(t, vs, ve)
        if key:sub(1, 12) == "urn:distrho:" then dpf = true end
        local name = key:sub(1, 12) == "urn:distrho:" and safe(key:sub(13)) or key_name(key, taken)
        remember(state, name, v, vkind, t:sub(vs, ve), { kind = kind, type = typ, int = vkind == "int", key = key })
        spans[#spans + 1] = { node = state, name = name, s = vs, e = ve }
        i = t:find("[;%]]", ve + 1)
        if not i or t:sub(i, i) == "]" then break end
        i = i + 1
      end
    end
    local rootname = "LV2"
    if dpf or ctx.hint == "dpf" then rootname = "DPF"
    elseif uri:find("^https?://lsp%-plug%.in/") then rootname = "LSP" end
    local root = juce.tree(rootname)
    root.children = { state, ports }
    if rootname == "DPF" then root.children = { state, ports } end
    remember(root, "plugin", uri, "string", uri)
    local function close()
      local edits = {}
      for _, s in ipairs(spans) do
        local text = text_of(s.node, s.name, turtle_text)
        if text == nil then error("LV2: a port or a key cannot be taken away (" .. s.name .. ")", 0) end
        if text ~= s.node.orig[s.name].text then edits[#edits + 1] = { s, text } end
      end
      table.sort(edits, function(a, b) return a[1].s > b[1].s end)
      local out = t
      for _, e in ipairs(edits) do out = out:sub(1, e[1].s - 1) .. e[2] .. out:sub(e[1].e + 1) end
      return out
    end
    local framework = rootname == "DPF" and "dpf" or (rootname == "LSP" and "lsp" or "lv2")
    return { root = root, close = close, params = "/" .. rootname .. "/Parameters", framework = framework,
      title = rootname == "LV2" and "LV2 (ports and state keys)" or (rootname .. " in LV2 (ports and state keys)"),
      layers = { "turtle" } }
  end,
})

-- --- JUCE --------------------------------------------------------------------------------

M.reader({
  name = "juce", title = "JUCE",
  detect = function() return true end,
  -- JUCE's own document: see `open` below.
  juce = true,
  open = function() error("JUCE documents come from plugstate.jucestate", 0) end,
})

-- --- anything else: the bytes ----------------------------------------------------------
-- The VST3 SDK and VSTGUI have no common form of state: each plugin
-- writes its own bytes with `IBStreamer`. They stay a `binary` property.
-- When most of the 32-bit words are plausible floats (as a plugin that
-- writes its parameters one after the other gives them), a `Floats` node
-- shows each of them by its place (`@at8`): a guess, which can be changed.

M.reader({
  name = "binary", title = "unknown (the bytes as they are)",
  detect = function() return true end,
  open = function(data)
    local root = juce.tree("State")
    remember(root, "data", { binary = data }, nil, data)
    local floats
    if #data >= 16 and #data % 4 == 0 and #data <= 262144 then
      local good, words = 0, #data / 4
      for at = 1, #data, 4 do
        local v = f32(data, at)
        if plausible(v) then good = good + 1 end
      end
      if good >= 0.9 * words then
        floats = juce.tree("Floats")
        for at = 1, #data, 4 do
          local v = f32(data, at)
          if plausible(v) then remember(floats, "at" .. (at - 1), v, nil, data:sub(at, at + 3)) end
        end
        root.children = { floats }
      end
    end
    local function close(r)
      local d = juce.get(r, "data")
      d = type(d) == "table" and d.binary or data
      local fl = juce.child(r, "Floats")
      if fl then
        local parts, last = {}, 1
        local changed = {}
        for _, p in ipairs(fl.props) do
          local o = fl.orig and fl.orig[p[1]]
          if not o or o.raw ~= p[2] then
            local at = tonumber(p[1]:match("^at(%d+)$"))
            if not at then error("binary: a float is named by its place (`at<n>`)", 0) end
            changed[#changed + 1] = { at = at + 1, v = juce.value(p[2]) }
          end
        end
        table.sort(changed, function(a, b) return a.at < b.at end)
        for _, c in ipairs(changed) do
          parts[#parts + 1] = d:sub(last, c.at - 1)
          parts[#parts + 1] = pack_f32(tonumber(c.v) or 0)
          last = c.at + 4
        end
        parts[#parts + 1] = d:sub(last)
        d = table.concat(parts)
      end
      return d
    end
    return { root = root, close = close, params = floats and "/State/Floats" or nil,
      notes = { "plugstate does not know this format: the bytes are a binary value" } }
  end,
})

-- The order in which the readers are asked: the formats with a magic of
-- their own first, then JUCE (which also reads plain XML), then text, then
-- the bytes.
local ORDER = { dpf = 1, lsp = 2, dplug = 3, iplug2 = 4, juce = 5, json = 6, lv2 = 7, binary = 8 }
table.sort(M.readers, function(a, b) return ORDER[a.name] < ORDER[b.name] end)

-- --- hints from the plugin's binary ------------------------------------------------------
-- The binary of a plugin names the framework it is made with. paw looks
-- for the plugin's binary in the plugin folders and reads it once; it
-- does not run it.

local MARKERS = {
  { "juce", "JucePlugin_" }, { "juce", "JUCE v" },
  { "iplug2", "iPlug2" }, { "dpf", "DISTRHO" }, { "lsp", "lsp-plug.in" },
  { "nih-plug", "nih_plug" }, { "dplug", "Dplug" }, { "hise", "N4hise" },
  { "vstgui", "VSTGUI" },
}

local folders = {
  vst3 = { "VST3_PATH", "/.vst3", "lib/vst3" }, clap = { "CLAP_PATH", "/.clap", "lib/clap" },
  lv2 = { "LV2_PATH", "/.lv2", "lib/lv2" },
}

local function squash(s) return (s or ""):lower():gsub("[^%w]", "") end

--- The binary of a plugin (`d.plugin` of `paw.api.device_get`), or nil.
function M.binary_of(plugin)
  if not plugin or not folders[plugin.format] then return nil end
  local f = folders[plugin.format]
  local dirs = {}
  for dir in (os.getenv(f[1]) or ""):gmatch("[^:]+") do dirs[#dirs + 1] = dir end
  local home, user = os.getenv("HOME"), os.getenv("USER")
  if #dirs == 0 then
    if home then dirs[#dirs + 1] = home .. f[2] dirs[#dirs + 1] = home .. "/.nix-profile/" .. f[3] end
    if user then dirs[#dirs + 1] = "/etc/profiles/per-user/" .. user .. "/" .. f[3] end
    dirs[#dirs + 1] = "/run/current-system/sw/" .. f[3]
    dirs[#dirs + 1] = "/usr/lib/" .. plugin.format
  end
  local want = squash(plugin.name)
  local function so_in(dir)
    for _, e in ipairs(paw.api.read_dir(dir)) do
      if not e.is_dir and (e.name:match("%.so$") or e.name:match("%.clap$")) then return dir .. "/" .. e.name end
    end
  end
  for _, dir in ipairs(dirs) do
    -- Never the bridges of Windows plugins: their own binary is elsewhere.
    if not dir:find("yabridge", 1, true) then
      for _, e in ipairs(paw.api.read_dir(dir)) do
        local stem = e.name:gsub("%.%w+$", "")
        if squash(stem) == want and not e.name:find("yabridge", 1, true) then
          local path = dir .. "/" .. e.name
          if plugin.format == "vst3" then
            local found = so_in(path .. "/Contents/x86_64-linux")
            if found then return found end
          elseif plugin.format == "clap" then
            if e.is_dir then
              local found = so_in(path)
              if found then return found end
            else
              return path
            end
          elseif plugin.format == "lv2" then
            local found = so_in(path)
            if found then return found end
          end
        end
      end
    end
  end
end

M.hint_cache = {}

--- The framework that the marker strings of a binary name: `name` and,
--- for JUCE, its version (`"juce", "8.0.15"`). Nil when there is none.
function M.markers(path)
  if not path then return nil end
  local cached = M.hint_cache[path]
  if cached then return cached.name, cached.version end
  local data = bytes.read_file(path) or ""
  local found, version = {}, data:match("JUCE v(%d+%.%d+%.%d+)")
  for _, m in ipairs(MARKERS) do
    if data:find(m[2], 1, true) then found[m[1]] = true end
  end
  -- The order: a framework that is made on top of another first.
  local name
  for _, n in ipairs({ "hise", "juce", "dpf", "lsp", "nih-plug", "dplug", "iplug2", "vstgui" }) do
    if found[n] then name = n break end
  end
  M.hint_cache[path] = { name = name or false, version = version }
  return name, version
end

-- --- opening a state ----------------------------------------------------------------------

--- Open a state (paw's base64) of `format`. `opts`: `hint` (a framework's
--- name), `param_info` (the host's parameters, as `device_get` gives them),
--- `desc` (a description of a JUCE plugin), `framework` (only that reader).
--- Gives the document; it says its framework in `doc.framework`.
function M.open(state64, format, opts)
  opts = opts or {}
  local raw = paw.bytes.unbase64(state64)
  local ctx = { hint = opts.hint, param_info = opts.param_info, desc = opts.desc, version = opts.version }
  local jucestate = require("plugstate.jucestate")
  local outer = M.outer(raw, format)
  local tried = {}
  for _, r in ipairs(M.readers) do
    if not opts.framework or opts.framework == r.name then
      if r.juce then
        local ok, doc = pcall(jucestate.open, state64, format, { desc = opts.desc })
        if ok then
          doc.framework = (ctx.hint == "hise") and "hise" or "juce"
          doc.title = doc.framework == "hise" and "HISE (on JUCE)" or ("JUCE" .. (ctx.version and (" " .. ctx.version) or ""))
          return doc
        end
        tried[#tried + 1] = "juce: " .. tostring(doc)
      else
        local data = (format == "lv2") and raw or outer.data
        local o = (format == "lv2") and { format = format, data = raw, wrap = function(new) return new end } or outer
        local fine, yes = pcall(r.detect, data, format, ctx)
        if fine and yes then
          local ok, made = pcall(r.open, data, format, ctx)
          if ok then return document(r, o, made, opts) end
          tried[#tried + 1] = r.name .. ": " .. tostring(made)
        end
      end
    end
  end
  error("no reader opens this state (" .. table.concat(tried, "; ") .. ")", 0)
end

--- The state of a device as a document, with the hints the device gives:
--- its parameters, the marker strings of its binary, the description of a
--- JUCE plugin.
function M.open_device(id, state64)
  local api = paw.api
  local d = api.device_get(id)
  if not d.plugin then error(d.name .. " is not a plugin", 0) end
  local hint, version = M.markers(M.binary_of(d.plugin))
  local desc = require("plugstate.jucestate").plugin_of(d)
  return M.open(state64 or api.device_state(id), d.plugin.format,
    { hint = hint or nil, version = version, param_info = d.param_info, desc = desc })
end

-- --- presets ------------------------------------------------------------------------------
-- A preset of plugstate (`.jucepreset`) is a base state and edits; the
-- edits are paths and parameters of the document, of any framework.

--- The state (paw's base64) of a preset for a device of `format`: the
--- preset's base (else `current`) with the edits.
function M.generate(preset, format, current, opts)
  opts = opts or {}
  local js = require("plugstate.jucestate")
  local base, base_format = preset.base, preset.format
  if not base then base, base_format = current, format end
  if not base then error("the preset has no base state, and there is no state of the device", 0) end
  local framework = preset.framework
  if framework == nil or framework == "juce" or framework == "hise" then
    -- A JUCE state goes into each format of the plugin.
    local ok, out = pcall(js.generate, preset, format, current, opts)
    if ok then return out end
    if framework then error(out, 0) end
  end
  local doc = M.open(base, base_format, { param_info = opts.param_info, hint = opts.hint })
  js.apply(doc, preset.edits)
  if base_format == format then return doc:write() end
  return doc:write_as(format, current)
end

return M
