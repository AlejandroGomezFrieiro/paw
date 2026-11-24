-- Singer presets: a vocal part's whole voice saved under a name, to give
-- another vocal part with one command.
--
-- A preset holds the singer, phonemizer, renderer, resampler, wavtool,
-- voice colour, the engine's other part options (AI pitch mode, unison,
-- key shift, ...) and the value each curve holds where it has no lane. It is
-- a JSON file in `<data dir>/utau/presets/<name>.json` (`~/.local/share/paw`
-- by default; `paw.opt.utau_presets_dir` puts them elsewhere).
-- Applying one replaces the part's voice whole: options it does not name
-- are cleared.
local api = paw.api
local utau = require("utau")
local json = require("utau.json")

local M = { VERSION = 1 }

function M.dir()
  local dir = paw.opt.utau_presets_dir
  if dir and dir ~= "" then return dir end
  return api.env().data_dir .. "/utau/presets"
end

--- A name as a file name.
function M.file_name(name)
  local s = tostring(name or ""):gsub('[/\\:%*%?"<>|%c]', "_"):gsub("^%s+", ""):gsub("%s+$", "")
  return s ~= "" and s or "Preset"
end

function M.path(name) return M.dir() .. "/" .. M.file_name(name) .. ".json" end

--- A vocal part's voice as a preset.
function M.from_part(part_id, name)
  local device = utau.device_of(part_id)
  if not device then error("not a vocal part", 0) end
  local config = utau.config(part_id)
  local options = {}
  for k, v in pairs(type(config.options) == "table" and config.options or {}) do
    options[k] = tostring(v)
  end
  if config.voice_color then options.subbank = config.voice_color end
  local curves = {}
  local d = api.device_get(device)
  for _, info in ipairs(d.param_info) do
    if info.key ~= "voice" then curves[info.key] = d.params[info.key] or info.default end
  end
  return {
    version = M.VERSION,
    name = name,
    singer = config.singer or "",
    phonemizer = config.phonemizer or "",
    renderer = config.renderer or "",
    resampler = config.resampler or "",
    wavtool = config.wavtool or "",
    pitchBendRange = 12,
    options = options,
    curves = curves,
  }
end

--- Save a part's voice under a name. Returns the file.
function M.save(part_id, name)
  if not name or name == "" then error("a preset needs a name", 0) end
  local preset = M.from_part(part_id, name)
  local dir = M.dir()
  pcall(paw.api.fs_mkdir, dir)
  local path = M.path(name)
  local file = io.open(path, "wb")
  if not file then error("cannot write " .. path, 0) end
  file:write(json.encode(preset, "  "), "\n")
  file:close()
  return path
end

--- Read a preset file, or nil when it is not one.
function M.read(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local text = file:read("*a")
  file:close()
  local ok, preset = pcall(json.decode, text)
  if not ok or type(preset) ~= "table" or preset.singer == nil then return nil end
  preset.name = preset.name or path:match("([^/]+)%.json$")
  preset.path = path
  return preset
end

--- Every preset, sorted by name.
function M.list()
  local out = {}
  local ok, entries = pcall(api.read_dir, M.dir())
  for _, entry in ipairs(ok and entries or {}) do
    if not entry.is_dir and entry.name:match("%.json$") then
      local preset = M.read(M.dir() .. "/" .. entry.name)
      if preset then out[#out + 1] = preset end
    end
  end
  table.sort(out, function(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end)
  return out
end

--- The preset a name means: exact first, then the first containing it.
function M.find(name)
  local list = M.list()
  local query = tostring(name):lower()
  for _, p in ipairs(list) do
    if tostring(p.name):lower() == query then return p end
  end
  for _, p in ipairs(list) do
    if tostring(p.name):lower():find(query, 1, true) then return p end
  end
end

--- Give a vocal part a preset's voice, as one edit.
function M.apply(part_id, preset)
  local device = utau.device_of(part_id)
  if not device then error("not a vocal part", 0) end
  if type(preset) ~= "table" then
    preset = M.find(preset) or error("no singer preset `" .. tostring(preset) .. "`", 0)
  end
  local options = {}
  for k, v in pairs(type(preset.options) == "table" and preset.options or {}) do
    if k ~= "subbank" and k ~= "bridge" and k ~= "bridgetrack" then options[k] = tostring(v) end
  end
  local function str(v) return type(v) == "string" and v ~= "" and v or false end
  local subbank = type(preset.options) == "table" and preset.options.subbank
  utau.configure(part_id, {
    singer = str(preset.singer),
    phonemizer = str(preset.phonemizer),
    renderer = str(preset.renderer),
    resampler = str(preset.resampler),
    wavtool = str(preset.wavtool),
    voice_color = str(subbank),
    options = next(options) and options or false,
  })
  local d = api.device_get(device)
  for _, info in ipairs(d.param_info) do
    local value = type(preset.curves) == "table" and tonumber(preset.curves[info.key])
    if info.key ~= "voice" then api.device_set_param(device, info.key, value or info.default) end
  end
  return preset
end

--- Delete a preset by name. Returns whether there was one.
function M.delete(name)
  local preset = M.find(name)
  if not preset then return false end
  return os.remove(preset.path) ~= nil
end

return M
