-- The adapters that come with plugstate. Each knows one family of plugins
-- and how to read and set the files its state names:
--
--   lv2      any LV2 plugin that lists properties (`patch:writable`): set
--            with a patch message, which the plugin loads like a file
--            chosen in its own window
--   nam      Neural Amp Modeler (LV2): its model, with what a .nam file
--            says of itself
--   lsp-ir   the impulse response files of LSP's convolution plugins
--   sfizz    sfizz as a VST3 plugin, which has no properties: the SFZ file
--            is written into its saved state (a state codec)
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local plugstate = require("plugstate")
local type types = require("paw.types")
local type util = require("paw.util")

local api = paw.api
local vst3 = {split = paw.bytes.vst3_split, join = paw.bytes.vst3_join}

local type Slot = plugstate.Slot
local type SlotValue = plugstate.SlotValue

local record M
  --- An LV2 property of a running plugin, as `device_call(id,
  --- "properties")` gives it: `type` is "path", "string", a kind of
  --- number, or "other".
  record Property
    key: string
    uri: string
    label: string
    type: string
    writable: boolean
    file_types: {string}
    value: SlotValue
  end

  --- What a .nam file says of itself.
  record NamInfo
    version: string
    architecture: string
    name: string
    gear: string
    tone: string
    loudness: number
  end

  --- sfizz's component state: the SFZ file in it, read and written.
  record SfizzCodec
    read_path: function(component: string): string, integer
    write_path: function(component: string, path: string): string
    path: function(state64: string): string
    with_path: function(state64: string, path: string): string
  end

  sfizz_codec: SfizzCodec
  --- The URI of Neural Amp Modeler's LV2 plugin.
  NAM: string
end

-- --- LV2 properties ----------------------------------------------------------

--- The properties of a running LV2 plugin (`device_call(id, "properties")`).
function M.properties(id: integer): {M.Property}
  local ok, text = pcall(api.device_call, id, "properties", "") as (boolean, string)
  if not ok then
    return {}
  end
  return api.json_decode(text) as {M.Property} or {}
end

local function what_of(p: M.Property): string
  local label = (p.label or ""):lower()
  if label:find("impulse") then
    return "impulse response"
  end
  if label:find("model") then
    return "model"
  end
  if label:find("sfz") or label:find("instrument") then
    return "instrument"
  end
  return label ~= "" and label or p.key
end

--- A change of a slot made from a property, by an adapter.
local type Extra = function(slot: Slot, p: M.Property)

--- The writable properties as slots.
function M.property_slots(id: integer, extra?: Extra): {Slot}
  local slots: {Slot} = {}
  for _, p in ipairs(M.properties(id)) do
    if p.writable and p.type ~= "other" then
      local slot: Slot = {
        key = p.key,
        uri = p.uri,
        label = p.label,
        what = what_of(p),
        kind = p.type == "path" and "file" or (p.type == "string" and "text" or "number"),
        types = #(p.file_types or {}) > 0 and p.file_types or nil,
        -- JSON's null is not a value.
        value = type(p.value) ~= "userdata" and p.value or nil,
      }
      if extra then
        extra(slot, p)
      end
      slots[#slots + 1] = slot
    end
  end
  return slots
end

--- What a property set to `value` holds in a patch message.
local record PropertySet
  property: string
  value: SlotValue
end

--- A load that sets a property: what `paw.api.device_load` takes.
function M.property_load(slot: Slot, value: SlotValue): types.PresetLoad
  if slot.kind == "number" then
    value = tonumber(value) or error("give a number", 0)
  end
  local set: PropertySet = {property = slot.uri, value = value}
  return {call = {method = "property.set", data = api.json_encode(set)}}
end

local function load_property(_: integer, _: types.Device, slot: Slot, value: SlotValue): types.PresetLoad
  return M.property_load(slot, value)
end

plugstate.adapter(
  {
    name = "lv2",
    desc = "LV2 plugins with properties (patch:writable): files and values set with a patch message",
    matches = function(d: types.Device): boolean
      return d.plugin and d.plugin.format == "lv2" and #M.properties(d.id) > 0
    end,
    slots = function(id: integer): {Slot} return M.property_slots(id) end,
    load = load_property,
  }
)

-- --- LSP's impulse responses -------------------------------------------------

local AUDIO = {"wav", "flac", "ogg", "aiff", "aif"}

plugstate.adapter(
  {
    name = "lsp-ir",
    desc = "LSP Impulse Responses and Impulse Reverb: their impulse response files",
    matches = function(d: types.Device): boolean
      return d.plugin
        and d.plugin.format == "lv2"
        and (d.plugin.id:find("^http://lsp%-plug%.in/plugins/lv2/impulse_re") ~= nil)
    end,
    slots = function(id: integer): {Slot}
      return M.property_slots(
        id, function(slot: Slot) slot.what, slot.types = "impulse response", slot.types or AUDIO end
      )
    end,
    load = load_property,
  }
)

-- --- Neural Amp Modeler ------------------------------------------------------

M.NAM = "http://github.com/mikeoliphant/neural-amp-modeler-lv2"

-- The end of the JSON object that starts at `open` in `head`, or nil.
local function object_end(head: string, open: integer): integer
  local depth = 0
  for i = open, #head do
    local c = head:sub(i, i)
    if c == "{" then
      depth = depth + 1
    elseif c == "}" then
      depth = depth - 1
      if depth == 0 then
        return i
      end
    end
  end
  return nil
end

local function text(v: util.Data): string
  return v is string and v or nil
end

--- What a .nam file says of itself: `{ architecture, name, gear, tone,
--- loudness, version }`. Only the start of the file is read, where its
--- metadata is.
function M.nam_info(path: string): M.NamInfo
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local head = f:read(16384) or ""
  f:close()
  local info: M.NamInfo = {
    version = head:match('"version"%s*:%s*"([^"]*)"'),
    architecture = head:match('"architecture"%s*:%s*"([^"]*)"'),
  }
  local at = head:find('"metadata"%s*:%s*{')
  if not at then
    return info
  end
  local open = head:find("{", at, true)
  local close = object_end(head, open)
  local ok, meta = pcall(api.json_decode, close and head:sub(open, close) or "") as (boolean, {string: util.Data})
  if ok and type(meta) == "table" then
    info.name = text(meta.name)
    local gear = {text(meta.gear_make), text(meta.gear_model)}
    info.gear = #gear > 0 and table.concat(gear, " ") or nil
    info.tone = text(meta.tone_type)
    local loudness = meta.loudness
    info.loudness = loudness is number and loudness or nil
  end
  return info
end

--- A few words on a .nam file: "WaveNet · Fender Deluxe · clean · -12.0 LUFS".
function M.nam_words(path: string): string
  local info = M.nam_info(path)
  if not info then
    return nil
  end
  local words: {string} = {}
  for _, w in ipairs({info.name or "", info.architecture or "", info.gear or "", info.tone or ""}) do
    if w ~= "" then
      words[#words + 1] = w
    end
  end
  if info.loudness then
    words[#words + 1] = string.format("%.1f dB loud", info.loudness)
  end
  return table.concat(words, " · ")
end

plugstate.adapter(
  {
    name = "nam",
    desc = "Neural Amp Modeler (LV2): its .nam model",
    matches = function(d: types.Device): boolean
      return d.plugin and d.plugin.format == "lv2" and d.plugin.id == M.NAM
    end,
    slots = function(id: integer): {Slot}
      return M.property_slots(id, function(slot: Slot) slot.what, slot.types = "model", slot.types or {"nam"} end)
    end,
    load = load_property,
    describe = M.nam_words,
  }
)

-- --- sfizz as a VST3 plugin: a state codec -----------------------------------
-- sfizz's component state starts with a 64-bit version, then the SFZ
-- file as a string: its length with the closing NUL (32 bits), the bytes,
-- the NUL. The rest stays as it is.

local codec: M.SfizzCodec = {}
M.sfizz_codec = codec

local function split(state: string): string, string
  local component, controller = vst3.split(state)
  if not component then
    error(controller, 0)
  end
  return component, controller
end

--- The SFZ file in sfizz's component state, and where the rest begins.
function codec.read_path(component: string): string, integer
  local len = paw.bytes.u32(component, 9)
  if not len or 12 + len > #component then
    error("not a state of sfizz", 0)
  end
  local path = component:sub(13, 12 + len):gsub("%z.*$", "")
  return path, 13 + len
end

function codec.write_path(component: string, path: string): string
  local _, rest = codec.read_path(component)
  return component:sub(1, 8) .. paw.bytes.le32(#path + 1) .. path .. "\0" .. component:sub(rest)
end

--- The SFZ file a saved state (base64) names.
function codec.path(state64: string): string
  local component = split(paw.bytes.unbase64(state64))
  return (codec.read_path(component))
end

--- The state (base64) with another SFZ file.
function codec.with_path(state64: string, path: string): string
  local component, controller = split(paw.bytes.unbase64(state64))
  return paw.bytes.base64(vst3.join(codec.write_path(component, path), controller))
end

plugstate.adapter(
  {
    name = "sfizz",
    desc = "sfizz (VST3): its SFZ instrument, written into the plugin's state",
    matches = function(d: types.Device): boolean
      return d.plugin and d.plugin.format == "vst3" and (d.plugin.name or ""):lower() == "sfizz"
    end,
    slots = function(id: integer): {Slot}
      local ok, path = pcall(function(): string return codec.path(api.device_state(id)) end) as (boolean, string)
      return {
        {
          key = "sfzfile",
          label = "SFZ file",
          what = "instrument",
          kind = "file",
          types = {"sfz"},
          value = ok and path or nil,
        },
      }
    end,
    load = function(id: integer, _: types.Device, _: Slot, value: SlotValue): types.PresetLoad
      local file = tostring(value)
      local f = io.open(file, "rb")
      if not f then
        error("there is no file " .. file, 0)
      end
      f:close()
      return {state = codec.with_path(api.device_state(id), file)}
    end,
  }
)

return M
