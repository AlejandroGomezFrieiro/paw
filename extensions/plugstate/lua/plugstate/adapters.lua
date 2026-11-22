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
local api = paw.api
local plugstate = require("plugstate")
local vst3 = { split = paw.bytes.vst3_split, join = paw.bytes.vst3_join }

local M = {}

-- --- LV2 properties ----------------------------------------------------------

--- The properties of a running LV2 plugin (`device_call(id, "properties")`).
function M.properties(id)
  local ok, text = pcall(api.device_call, id, "properties", "")
  if not ok then return {} end
  return paw.json.decode(text) or {}
end

local function what_of(p)
  local label = (p.label or ""):lower()
  if label:find("impulse") then return "impulse response" end
  if label:find("model") then return "model" end
  if label:find("sfz") or label:find("instrument") then return "instrument" end
  return label ~= "" and label or p.key
end

--- The writable properties as slots.
function M.property_slots(id, extra)
  local slots = {}
  for _, p in ipairs(M.properties(id)) do
    if p.writable and p.type ~= "other" then
      local slot = {
        key = p.key,
        uri = p.uri,
        label = p.label,
        what = what_of(p),
        kind = p.type == "path" and "file" or (p.type == "string" and "text" or "number"),
        types = #(p.file_types or {}) > 0 and p.file_types or nil,
        value = type(p.value) ~= "userdata" and p.value or nil,
      }
      if extra then extra(slot, p) end
      slots[#slots + 1] = slot
    end
  end
  return slots
end

--- A load that sets a property: what `paw.api.device_load` takes.
function M.property_load(slot, value)
  if slot.kind == "number" then value = tonumber(value) or error("give a number", 0) end
  return {
    call = { method = "property.set", data = paw.json.encode({ property = slot.uri, value = value }) },
  }
end

plugstate.adapter({
  name = "lv2",
  desc = "LV2 plugins with properties (patch:writable): files and values set with a patch message",
  matches = function(d) return d.plugin and d.plugin.format == "lv2" and #M.properties(d.id) > 0 end,
  slots = function(id) return M.property_slots(id) end,
  load = function(_, _, slot, value) return M.property_load(slot, value) end,
})

-- --- LSP's impulse responses -------------------------------------------------

local AUDIO = { "wav", "flac", "ogg", "aiff", "aif" }

plugstate.adapter({
  name = "lsp-ir",
  desc = "LSP Impulse Responses and Impulse Reverb: their impulse response files",
  matches = function(d)
    return d.plugin
      and d.plugin.format == "lv2"
      and (d.plugin.id:find("^http://lsp%-plug%.in/plugins/lv2/impulse_re") ~= nil)
  end,
  slots = function(id)
    return M.property_slots(id, function(slot)
      slot.what, slot.types = "impulse response", slot.types or AUDIO
    end)
  end,
  load = function(_, _, slot, value) return M.property_load(slot, value) end,
})

-- --- Neural Amp Modeler ------------------------------------------------------

M.NAM = "http://github.com/mikeoliphant/neural-amp-modeler-lv2"

--- What a .nam file says of itself: `{ architecture, name, gear, tone,
--- loudness, version }`. Only the start of the file is read, where its
--- metadata is.
function M.nam_info(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local head = f:read(16384) or ""
  f:close()
  local info = {
    version = head:match('"version"%s*:%s*"([^"]*)"'),
    architecture = head:match('"architecture"%s*:%s*"([^"]*)"'),
  }
  local at = head:find('"metadata"%s*:%s*{')
  if at then
    local open = head:find("{", at, true)
    local depth, close = 0, nil
    for i = open, #head do
      local c = head:sub(i, i)
      if c == "{" then
        depth = depth + 1
      elseif c == "}" then
        depth = depth - 1
        if depth == 0 then
          close = i
          break
        end
      end
    end
    local ok, meta = pcall(paw.json.decode, close and head:sub(open, close) or "")
    if ok and type(meta) == "table" then
      local function text(v) return type(v) == "string" and v or nil end
      info.name = text(meta.name)
      local gear = { text(meta.gear_make), text(meta.gear_model) }
      info.gear = #gear > 0 and table.concat(gear, " ") or nil
      info.tone = text(meta.tone_type)
      info.loudness = type(meta.loudness) == "number" and meta.loudness or nil
    end
  end
  return info
end

--- A few words on a .nam file: "WaveNet · Fender Deluxe · clean · -12.0 LUFS".
function M.nam_words(path)
  local info = M.nam_info(path)
  if not info then return nil end
  local words = {}
  for _, key in ipairs({ "name", "architecture", "gear", "tone" }) do
    local w = info[key]
    if w and w ~= "" then words[#words + 1] = w end
  end
  if info.loudness then words[#words + 1] = string.format("%.1f dB loud", info.loudness) end
  return table.concat(words, " · ")
end

plugstate.adapter({
  name = "nam",
  desc = "Neural Amp Modeler (LV2): its .nam model",
  matches = function(d) return d.plugin and d.plugin.format == "lv2" and d.plugin.id == M.NAM end,
  slots = function(id)
    return M.property_slots(id, function(slot)
      slot.what, slot.types = "model", slot.types or { "nam" }
    end)
  end,
  load = function(_, _, slot, value) return M.property_load(slot, value) end,
  describe = M.nam_words,
})

-- --- sfizz as a VST3 plugin: a state codec -----------------------------------
-- sfizz's component state starts with a 64-bit version, then the SFZ
-- file as a string: its length with the closing NUL (32 bits), the bytes,
-- the NUL. The rest stays as it is.

local codec = {}
M.sfizz_codec = codec

local function split(state)
  local component, controller = vst3.split(state)
  if not component then error(controller, 0) end
  return component, controller
end

--- The SFZ file in sfizz's component state, and where the rest begins.
function codec.read_path(component)
  local len = paw.bytes.u32(component, 9)
  if not len or 12 + len > #component then error("not a state of sfizz", 0) end
  local path = component:sub(13, 12 + len):gsub("%z.*$", "")
  return path, 13 + len
end

function codec.write_path(component, path)
  local _, rest = codec.read_path(component)
  return component:sub(1, 8) .. paw.bytes.le32(#path + 1) .. path .. "\0" .. component:sub(rest)
end

--- The SFZ file a saved state (base64) names.
function codec.path(state64)
  local component = split(paw.bytes.unbase64(state64))
  return (codec.read_path(component))
end

--- The state (base64) with another SFZ file.
function codec.with_path(state64, path)
  local component, controller = split(paw.bytes.unbase64(state64))
  return paw.bytes.base64(vst3.join(codec.write_path(component, path), controller))
end

plugstate.adapter({
  name = "sfizz",
  desc = "sfizz (VST3): its SFZ instrument, written into the plugin's state",
  matches = function(d) return d.plugin and d.plugin.format == "vst3" and (d.plugin.name or ""):lower() == "sfizz" end,
  slots = function(id)
    local ok, path = pcall(function() return codec.path(api.device_state(id)) end)
    return {
      {
        key = "sfzfile",
        label = "SFZ file",
        what = "instrument",
        kind = "file",
        types = { "sfz" },
        value = ok and path or nil,
      },
    }
  end,
  load = function(id, _, _, value)
    local f = io.open(value, "rb")
    if not f then error("there is no file " .. value, 0) end
    f:close()
    return { state = codec.with_path(api.device_state(id), value) }
  end,
})

return M
