-- Small pictures of what a built-in effect is doing, drawn under its name
-- in the device panel: the equaliser's curve, gain reduction, loudness and
-- the tuner's needle. Each is `{ rows = n, draw = function(buf, device) }`,
-- reading the device live through `paw.params.read`.
local M = {}

local function read(device, method, data)
  local ok, value = pcall(paw.params.read, device.id, method, data)
  return ok and value or nil
end

local function db_text(v, unit)
  if not v or v <= -150 then return "-inf" .. (unit and " " .. unit or "") end
  return string.format("%.1f", v) .. (unit and " " .. unit or "")
end

-- The equaliser: its response over ±18 dB, 0 dB marked, the frequencies
-- under it and each band that is on numbered where it sits.
local EQ_RANGE = 18
M.eq = {
  rows = 5,
  draw = function(buf, device)
    local g = paw.draw.g
    local w = buf.width
    local rows = buf.height - 1
    if w < 8 then return end
    local curve = read(device, "curve", w * 2) or {}
    local mid = math.floor(rows / 2)
    buf:fill(0, mid, w, 1, g.meter_off, "MeterOff")
    paw.draw.curve(buf:sub(0, 0, w, rows), 0, rows, function(i)
      local v = curve[i + 1]
      return v and (v + EQ_RANGE) / (2 * EQ_RANGE)
    end, "ParamBar")
    -- Frequencies along the bottom.
    local function col(f) return math.floor(math.log(f / 20) / math.log(1000) * (w - 1) + 0.5) end
    for _, mark in ipairs({ { 100, "100" }, { 1000, "1k" }, { 10000, "10k" } }) do
      local x = col(mark[1])
      if x + #mark[2] <= w then buf:text(x, rows, mark[2], "Faint") end
    end
    -- The bands that are on, by number, at their frequency and gain.
    local p = device.params
    for b = 1, 8 do
      if (p["b" .. b .. "_on"] or 0) >= 0.5 then
        local gain = p["b" .. b .. "_gain"] or 0
        local kind = math.floor((p["b" .. b .. "_type"] or 3) + 0.5)
        if kind < 2 or kind > 4 then gain = 0 end
        local y = math.floor((1 - (gain + EQ_RANGE) / (2 * EQ_RANGE)) * (rows - 1) + 0.5)
        buf:text(
          paw.util.clamp(col(p["b" .. b .. "_freq"] or 1000), 0, w - 1),
          paw.util.clamp(y, 0, rows - 1),
          tostring(b),
          "Bright"
        )
      end
    end
    buf:text(w - 7, 0, "+" .. EQ_RANGE .. " dB", "Faint")
  end,
}

-- Gain reduction: a bar growing from the left over 24 dB, and the number.
local function reduction(buf, device)
  local g = paw.draw.g
  local m = read(device, "meters") or {}
  local gr = math.min(0, m.gr or 0)
  local text = string.format("%5.1f dB", gr)
  buf:text(0, 0, "GR", "Dim")
  local width = math.max(1, buf.width - 4 - #text - 1)
  local lit = paw.util.clamp(-gr / 24, 0, 1) * width
  for cell = 0, width - 1 do
    local amount = lit - cell
    local glyph = amount >= 0.75 and g.meter_full or amount >= 0.25 and g.meter_half or g.meter_off
    buf:text(3 + cell, 0, glyph, amount >= 0.25 and "MeterMid" or "MeterOff")
  end
  buf:text(buf.width - #text, 0, text, gr < -0.05 and "Bright" or "Dim")
end
M.compressor = { rows = 1, draw = reduction }
M.gate = { rows = 1, draw = reduction }
M.limiter = { rows = 1, draw = reduction }

-- The loudness meter: momentary, short-term and integrated, then the peaks
-- and the correlation.
M.meter = {
  rows = 2,
  draw = function(buf, device)
    local m = read(device, "meters") or {}
    local x = buf:text(0, 0, "M ", "Dim")
    x = x + buf:text(x, 0, db_text(m.momentary), "Bright")
    x = x + buf:text(x, 0, "  S ", "Dim")
    x = x + buf:text(x, 0, db_text(m.short_term), "Bright")
    x = x + buf:text(x, 0, "  I ", "Dim")
    x = x + buf:text(x, 0, db_text(m.integrated), "Bright")
    buf:text(x, 0, " LUFS", "Dim")
    x = buf:text(0, 1, "TP ", "Dim")
    x = x + buf:text(x, 1, db_text(m.true_peak, "dBTP"), (m.true_peak or -200) > -1 and "Error" or "Param")
    x = x + buf:text(x, 1, "  corr ", "Dim")
    local corr = m.correlation or 0
    buf:text(x, 1, string.format("%+.2f", corr), corr < 0 and "Error" or "Param")
  end,
}

-- The tuner: the note, a needle over ±50 cents with the middle marked, and
-- the cents and the frequency.
M.tuner = {
  rows = 2,
  draw = function(buf, device)
    local g = paw.draw.g
    local p = read(device, "pitch") or {}
    local sure = (p.confidence or 0) > 0.6 and p.note ~= "-"
    local note = sure and tostring(p.note) or "-"
    buf:text(0, 0, string.format("%-4s", note), sure and "Bright" or "Dim")
    local width = math.max(5, buf.width - 6)
    if width % 2 == 0 then width = width - 1 end
    local centre = math.floor(width / 2)
    buf:fill(5, 0, width, 1, g.slider_off, "ParamBarOff")
    buf:text(5 + centre, 0, g.pan_mark, "Dim")
    if sure then
      local cents = p.cents or 0
      local at = paw.util.clamp(centre + math.floor(cents / 50 * centre + 0.5), 0, width - 1)
      local tuned = math.abs(cents) < 3
      buf:text(5 + at, 0, g.knob, tuned and "MeterLow" or math.abs(cents) < 15 and "MeterMid" or "MeterHigh")
      buf:text(5, 1, string.format("%+.1f ct  %.2f Hz", cents, p.freq or 0), tuned and "MeterLow" or "Param")
    else
      buf:text(5, 1, "play a single note", "Faint")
    end
  end,
}

return M
