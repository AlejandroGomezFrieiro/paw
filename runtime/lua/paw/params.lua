-- How a device parameter is shown and moved: its value as text in its unit
-- (`2.5 kHz`, `-18.0 dB`, `4:1`, `120 ms`), where it sits on a slider (on a
-- log scale for frequencies, times and ratios), and how far a key moves it.
-- Both frontends go through here, so a device reads the same everywhere.
--
-- `paw.params.read(device, method, data)` asks a built-in device for what it
-- measures or draws (an equaliser's curve, a compressor's gain reduction, a
-- meter's loudness, a tuner's pitch) and turns the answer into Lua values.
local M = {}

local LOG_UNITS = { Hz = true, ms = true, s = true, Q = true, [":1"] = true }

--- True if the parameter moves on a log scale.
function M.is_log(p) return LOG_UNITS[p.unit] and p.min > 0 and p.max / p.min >= 8 and #p.choices == 0 end

-- A number with at most `digits` decimals and no trailing zeros.
local function trim(value, digits)
  local s = string.format("%." .. digits .. "f", value)
  if digits > 0 then s = s:gsub("0+$", ""):gsub("%.$", "") end
  if s == "-0" then s = "0" end
  return s
end

local function generic(p, value)
  local range = p.max - p.min
  local digits = range >= 100 and 0 or range >= 10 and 1 or range > 2 and 2 or 3
  local number = string.format("%." .. digits .. "f", value)
  return p.unit ~= "" and number .. " " .. p.unit or number
end

local FORMAT = {
  dB = function(v) return string.format("%.1f dB", v) end,
  Hz = function(v)
    if v >= 1000 then return trim(v / 1000, v >= 10000 and 1 or 2) .. " kHz" end
    return trim(v, v < 100 and 1 or 0) .. " Hz"
  end,
  ms = function(v)
    if v >= 1000 then return trim(v / 1000, 2) .. " s" end
    return trim(v, v < 10 and 2 or v < 100 and 1 or 0) .. " ms"
  end,
  s = function(v)
    if v < 1 then return trim(v * 1000, v < 0.01 and 2 or v < 0.1 and 1 or 0) .. " ms" end
    return trim(v, v < 10 and 2 or 1) .. " s"
  end,
  [":1"] = function(v, p)
    if v >= p.max and p.max >= 50 then return "∞:1" end
    return trim(v, v < 10 and 1 or 0) .. ":1"
  end,
  ["%"] = function(v) return trim(v, 0) .. " %" end,
  Q = function(v) return trim(v, v < 10 and 2 or 1) end,
  st = function(v) return trim(v, 2) .. " st" end,
  ct = function(v) return trim(v, 0) .. " ct" end,
}

--- The value as text, in the parameter's unit.
function M.format(p, value)
  if value == nil then return "" end
  if #p.choices > 0 then
    -- Steps from `min` to `max`: one for each choice.
    local span = p.max - p.min
    local at = span > 0 and math.floor((value - p.min) / span * (#p.choices - 1) + 0.5) or 0
    return p.choices[at + 1] or tostring(value)
  end
  local f = FORMAT[p.unit]
  return f and f(value, p) or generic(p, value)
end

--- Where the value sits on a slider, 0 to 1.
function M.fraction(p, value)
  if p.max <= p.min then return 0 end
  local f
  if M.is_log(p) then
    f = math.log(math.max(value, p.min) / p.min) / math.log(p.max / p.min)
  else
    f = (value - p.min) / (p.max - p.min)
  end
  return math.max(0, math.min(1, f))
end

--- The value at a slider position, 0 to 1.
function M.from_fraction(p, fraction)
  fraction = math.max(0, math.min(1, fraction))
  if M.is_log(p) then return p.min * (p.max / p.min) ^ fraction end
  return p.min + fraction * (p.max - p.min)
end

-- A value rounded to what its unit shows, so that keys land on round numbers.
local function round(p, value)
  local q
  if p.unit == "dB" then
    q = 0.1
  elseif M.is_log(p) then
    local mag = 10 ^ math.floor(math.log(math.abs(value), 10))
    q = mag / 100
  end
  if not q then return value end
  return math.floor(value / q + 0.5) * q
end

--- The value `steps` key presses away: a hundredth of the slider each, one
--- option at a time for a choice.
function M.step(p, value, steps)
  if #p.choices > 0 then return math.max(p.min, math.min(p.max, math.floor(value + 0.5) + (steps > 0 and 1 or -1))) end
  local moved = round(p, M.from_fraction(p, M.fraction(p, value) + steps / 100))
  if moved == value then moved = M.from_fraction(p, M.fraction(p, value) + steps / 100) end
  return math.max(p.min, math.min(p.max, moved))
end

--- Ask a built-in device for a reading: a list of numbers (`curve`,
--- `spectrum`) or a table of named numbers (`meters`, `pitch`).
function M.read(device, method, data)
  local id = type(device) == "table" and device.id or device
  local text = paw.api.device_call(id, method, data and tostring(data) or nil)
  if text:find("\n") then
    local out = {}
    for name, value in text:gmatch("(%S+) (%S+)") do
      out[name] = tonumber(value) or value
    end
    return out
  end
  local out = {}
  for n in text:gmatch("%S+") do
    out[#out + 1] = tonumber(n)
  end
  return out
end

--- The built-in presets of a device kind: a list of `{ name, params }`.
function M.presets(kind) return require("paw.device_presets")[kind] or {} end

--- A preset's value for a parameter as a number: a choice may be named.
function M.preset_value(p, value)
  if type(value) == "string" then
    for i, choice in ipairs(p.choices) do
      if choice == value then return i - 1 end
    end
    error("`" .. p.key .. "` has no choice `" .. value .. "`", 2)
  end
  return value
end

--- Set a device to one of the presets of its kind, by name. This is the
--- same as a load with `paw.fx.load` (`:preset`): one undo step, and the
--- device then has that preset.
function M.apply(device, name)
  local id = type(device) == "table" and device.id or device
  local d = paw.api.device_get(id)
  for _, preset in ipairs(M.presets(d.kind)) do
    if preset.name == name then
      paw.fx.load(id, { name = preset.name, params = preset.params, factory = true })
      return preset
    end
  end
  error("no preset `" .. tostring(name) .. "` for " .. d.kind, 2)
end

return M
