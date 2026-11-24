-- Windows for the built-in effects in a graphical frontend (see
-- runtime/lua/paw/canvas.tl), each opened by a command that works in the
-- terminal too, where the device panel shows the same things smaller:
--
--   :eq         the part's equaliser (one is added if it has none): its
--               curve over a grid, a dot per band. Drag a dot to move the
--               band (left and right for frequency, up and down for gain),
--               the wheel over it changes its Q, a double click on a dot
--               turns the band off, on empty space turns the nearest band
--               that is off on as a bell there.
--   :tuner      the part's tuner (added if missing): the note, a needle
--               over ±50 cents, the frequency.
--   :loudness   the master's meter (added at the end if missing): loudness,
--               peaks, correlation and the spectrum.
--
-- The terminal keeps the keyboard in the device panel, on the device.
local api = paw.api
local util = paw.util
local c = require("paw.theme").palette
local M = { device = {} }

local function read(id, method, data)
  local ok, value = pcall(paw.params.read, id, method, data)
  return ok and value or nil
end

local function exists(id) return id and (pcall(api.device_get, id)) end

local function mix(a, b, t) return paw.draw.mix(a, b, t) end

--- The first device of `kind` on a part, or a new one.
local function device_on(part, kind)
  for _, d in ipairs(part:devices()) do
    if d:get().kind == kind then return d end
  end
  return part:add_device(kind)
end

--- Show the device in the panel, with the keyboard on it, and its window.
local function open(view, device, opts)
  M.device[view] = device.id
  local inspector = paw.ui.views:get("inspector")
  if inspector then inspector:show(device.id) end
  paw.canvas.open(view, opts)
  pcall(paw.ui.focus, "inspector")
end

-- The equaliser ---------------------------------------------------------------

local EQ = { top = 40, left = 44, right = 16, bottom = 28, range = 18 }
local eq = { drag = nil, hover = nil }
paw.seats.keep("eq_window", function() return eq end, function(e) eq = e end, function() return {} end)

local function eq_area(width, height) return EQ.left, EQ.top, width - EQ.left - EQ.right, height - EQ.top - EQ.bottom end

local function freq_x(f, x, w) return x + math.log(f / 20) / math.log(1000) * w end
local function x_freq(px, x, w) return 20 * 1000 ^ util.clamp((px - x) / w, 0, 1) end
local function gain_y(db, y, h) return y + (1 - (db + EQ.range) / (2 * EQ.range)) * h end
local function y_gain(py, y, h) return util.clamp((1 - (py - y) / h) * 2 * EQ.range - EQ.range, -24, 24) end

local GAIN_TYPES = { [2] = true, [3] = true, [4] = true }

--- The bands as they are drawn: number, on, type, frequency, gain, Q, and
--- where the dot is.
local function bands(d, width, height)
  local x, y, w, h = eq_area(width, height)
  local out = {}
  for b = 1, 8 do
    local p = function(k) return d.params["b" .. b .. "_" .. k] end
    local kind = math.floor(p("type") + 0.5)
    local gain = GAIN_TYPES[kind] and p("gain") or 0
    out[b] = {
      index = b,
      on = p("on") >= 0.5,
      kind = kind,
      freq = p("freq"),
      gain = p("gain"),
      q = p("q"),
      x = freq_x(p("freq"), x, w),
      y = gain_y(gain, y, h),
    }
  end
  return out
end

local function band_at(list, px, py)
  local best, dist = nil, 14
  for _, b in ipairs(list) do
    local d = math.sqrt((b.x - px) ^ 2 + (b.y - py) ^ 2)
    if d < dist and b.on then
      best, dist = b, d
    end
  end
  return best
end

local BAND_COLOURS = { "#e0605a", "#e58a45", "#d9ab3a", "#a9c04a", "#45b3a3", "#4aa3df", "#9a7ff0", "#e06b9a" }

paw.ui.view("eq_window", {
  focusable = false,
  paint = function(_, g, ctx)
    local width, height = ctx.width, ctx.height
    g:rect(0, 0, width, height, { fill = c.bg })
    local id = M.device.eq_window
    if not exists(id) then
      g:text(16, 16, "The equaliser is gone. :eq opens one.", { color = c.dim, size = 14 })
      return
    end
    local d = api.device_get(id)
    local part = api.part_get(d.part)
    g:rect(0, 0, width, 30, { fill = c.bg_alt })
    g:text(
      12,
      7,
      part.name .. "  ·  EQ" .. (d.bypass and "  (bypassed)" or ""),
      { color = c.bright, size = 14, bold = true }
    )
    local x, y, w, h = eq_area(width, height)
    -- Grid: decibels every 6, frequencies at the round numbers.
    for db = -EQ.range, EQ.range, 6 do
      local ly = gain_y(db, y, h)
      g:line(x, ly, x + w, ly, { color = db == 0 and c.line_hi or c.line, width = 1 })
      g:text(x - 6, ly - 7, (db > 0 and "+" or "") .. db, { color = c.faint, size = 11, align = "right" })
    end
    for _, f in ipairs({ 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000 }) do
      local lx = freq_x(f, x, w)
      g:line(lx, y, lx, y + h, { color = c.line, width = 1 })
      local label = f >= 1000 and (f / 1000) .. "k" or tostring(f)
      g:text(lx, y + h + 6, label, { color = c.faint, size = 11, align = "center" })
    end
    -- The curve, filled down to 0 dB.
    local n = math.max(32, math.floor(w / 3))
    local curve = read(id, "curve", n) or {}
    local points, fill = {}, { x, gain_y(0, y, h) }
    for i, v in ipairs(curve) do
      local px, py = x + (i - 1) / (n - 1) * w, gain_y(util.clamp(v, -EQ.range - 6, EQ.range + 6), y, h)
      points[#points + 1], points[#points + 2] = px, py
      fill[#fill + 1], fill[#fill + 2] = px, py
    end
    fill[#fill + 1], fill[#fill + 2] = x + w, gain_y(0, y, h)
    local inside = g:sub(x, y, w, h)
    if #curve > 1 then
      for i = 1, #fill, 2 do
        fill[i], fill[i + 1] = fill[i] - x, fill[i + 1] - y
      end
      inside:poly(fill, { fill = mix(c.bg, c.accent, 0.14) })
      g:poly(points, { color = c.accent, width = 2 })
    end
    local list = bands(d, width, height)
    for _, b in ipairs(list) do
      if b.on then
        local colour = BAND_COLOURS[b.index]
        local r = (eq.hover == b.index or (eq.drag and eq.drag.band == b.index)) and 9 or 7
        g:rect(b.x - r, b.y - r, 2 * r, 2 * r, { fill = colour, stroke = c.bg, width = 2, radius = r })
        g:text(b.x, b.y - 6, tostring(b.index), { color = c.bg, size = 10, bold = true, align = "center" })
      end
    end
    -- What the band under the pointer, or being dragged, is set to.
    local focus = eq.drag and eq.drag.band or eq.hover
    local b = focus and list[focus]
    if b then
      local info = d.param_info
      local function fmt(key)
        for _, p in ipairs(info) do
          if p.key == key then return paw.params.format(p, d.params[key]) end
        end
        return ""
      end
      local k = "b" .. b.index .. "_"
      local text = string.format(
        "%d  %s  %s  %s  Q %s",
        b.index,
        fmt(k .. "type"),
        fmt(k .. "freq"),
        fmt(k .. "gain"),
        fmt(k .. "q")
      )
      g:text(width - 12, 8, text, { color = c.fg, size = 13, align = "right", width = width / 2 })
    else
      g:text(
        width - 12,
        9,
        "drag a dot · wheel for Q · double click",
        { color = c.faint, size = 11, align = "right", width = width / 2 }
      )
    end
  end,
  pointer = function(_, e)
    local id = M.device.eq_window
    if not exists(id) then return end
    local width, height = eq.size and eq.size[1] or 900, eq.size and eq.size[2] or 420
    local d = api.device_get(id)
    local list = bands(d, width, height)
    local x, y, w, h = eq_area(width, height)
    if e.kind == "down" then
      local b = band_at(list, e.x, e.y)
      eq.drag = b and { band = b.index } or nil
      eq.hover = b and b.index or nil
    elseif e.kind == "move" and eq.drag then
      local b = list[eq.drag.band]
      local k = "b" .. b.index .. "_"
      api.device_set_param(id, k .. "freq", util.clamp(x_freq(e.x, x, w), 20, 20000))
      if GAIN_TYPES[b.kind] then api.device_set_param(id, k .. "gain", y_gain(e.y, y, h)) end
    elseif e.kind == "up" then
      eq.drag = nil
    elseif e.kind == "wheel" then
      local b = band_at(list, e.x, e.y) or (eq.hover and list[eq.hover])
      if b then
        local q = util.clamp(b.q * 1.12 ^ ((e.dy or 0) > 0 and 1 or -1), 0.1, 18)
        api.device_set_param(id, "b" .. b.index .. "_q", q)
        eq.hover = b.index
      end
    elseif e.kind == "double" then
      local b = band_at(list, e.x, e.y)
      if b then
        api.device_set_param(id, "b" .. b.index .. "_on", 0)
      else
        -- The band that is off and nearest in frequency comes on, as a bell.
        local f = x_freq(e.x, x, w)
        local best, dist
        for _, cand in ipairs(list) do
          local dd = math.abs(math.log(cand.freq / f))
          if not cand.on and (not best or dd < dist) then
            best, dist = cand, dd
          end
        end
        if best then
          local k = "b" .. best.index .. "_"
          api.device_set_param(id, k .. "type", 3)
          api.device_set_param(id, k .. "freq", f)
          api.device_set_param(id, k .. "gain", y_gain(e.y, y, h))
          api.device_set_param(id, k .. "on", 1)
        end
      end
    end
  end,
})

-- The size the window was last painted at, for the pointer's arithmetic.
local eq_paint = paw.ui.views:get("eq_window").paint
paw.ui.views:get("eq_window").paint = function(self, g, ctx)
  eq.size = { ctx.width, ctx.height }
  return eq_paint(self, g, ctx)
end

-- The tuner -------------------------------------------------------------------

paw.ui.view("tuner_window", {
  focusable = false,
  paint = function(_, g, ctx)
    local width, height = ctx.width, ctx.height
    g:rect(0, 0, width, height, { fill = c.bg })
    local id = M.device.tuner_window
    if not exists(id) then
      g:text(16, 16, "The tuner is gone. :tuner opens one.", { color = c.dim, size = 14 })
      return
    end
    local p = read(id, "pitch") or {}
    local sure = (p.confidence or 0) > 0.6 and p.note ~= "-"
    local cents = sure and (p.cents or 0) or 0
    local tuned = sure and math.abs(cents) < 3
    local colour = not sure and c.faint or tuned and c.meter_low or math.abs(cents) < 15 and c.meter_mid or c.meter_high
    g:text(
      width / 2,
      height * 0.12,
      sure and tostring(p.note) or "–",
      { color = colour, size = 64, bold = true, align = "center" }
    )
    -- The scale: ±50 cents, a tick every 10, the middle long.
    local x0, x1, sy = width * 0.1, width * 0.9, height * 0.62
    g:line(x0, sy, x1, sy, { color = c.line_hi, width = 2 })
    for k = -50, 50, 10 do
      local tx = x0 + (k + 50) / 100 * (x1 - x0)
      local long = k == 0
      g:line(
        tx,
        sy - (long and 22 or 10),
        tx,
        sy + (long and 22 or 10),
        { color = long and c.dim or c.line_hi, width = long and 2 or 1 }
      )
      if k % 50 == 0 then
        g:text(tx, sy + 28, (k > 0 and "+" or "") .. k, { color = c.faint, size = 11, align = "center" })
      end
    end
    if sure then
      local nx = x0 + (util.clamp(cents, -50, 50) + 50) / 100 * (x1 - x0)
      g:rect(nx - 4, sy - 30, 8, 60, { fill = colour, radius = 3 })
      g:text(
        width / 2,
        height * 0.80,
        string.format("%+.1f cents   %.2f Hz", cents, p.freq or 0),
        { color = c.fg, size = 15, align = "center" }
      )
    else
      g:text(width / 2, height * 0.80, "play a single note", { color = c.faint, size = 14, align = "center" })
    end
  end,
})

-- The loudness meter ------------------------------------------------------------

local function lufs(v) return (not v or v <= -150) and "–" or string.format("%.1f", v) end

paw.ui.view("meter_window", {
  focusable = false,
  paint = function(_, g, ctx)
    local width, height = ctx.width, ctx.height
    g:rect(0, 0, width, height, { fill = c.bg })
    local id = M.device.meter_window
    if not exists(id) then
      g:text(16, 16, "The meter is gone. :loudness opens one.", { color = c.dim, size = 14 })
      return
    end
    local m = read(id, "meters") or {}
    local cols = {
      { "Momentary", lufs(m.momentary), "LUFS" },
      { "Short-term", lufs(m.short_term), "LUFS" },
      { "Integrated", lufs(m.integrated), "LUFS" },
      { "True peak", lufs(m.true_peak), "dBTP" },
      { "Correlation", m.correlation and string.format("%+.2f", m.correlation) or "–", "" },
    }
    local cw = width / #cols
    for i, col in ipairs(cols) do
      local cx = (i - 1) * cw + cw / 2
      g:text(cx, 14, col[1], { color = c.dim, size = 12, align = "center" })
      local hot = col[3] == "dBTP" and (m.true_peak or -200) > -1
      g:text(cx, 32, col[2], { color = hot and c.red or c.bright, size = 26, bold = true, align = "center" })
      g:text(cx, 64, col[3], { color = c.faint, size = 11, align = "center" })
    end
    -- The spectrum below, from -90 to 0 dB.
    local x, y, w, h = 40, 92, width - 56, height - 120
    g:rect(x, y, w, h, { fill = c.bg_dark })
    for db = -80, 0, 20 do
      local ly = y + -db / 90 * h
      g:line(x, ly, x + w, ly, { color = c.line, width = 1 })
      g:text(x - 6, ly - 7, tostring(db), { color = c.faint, size = 10, align = "right" })
    end
    local n = math.max(16, math.floor(w / 6))
    local bands = read(id, "spectrum", n) or {}
    local bw = w / n
    for i, v in ipairs(bands) do
      local bh = util.clamp((v + 90) / 90, 0, 1) * h
      if bh > 0.5 then
        g:rect(x + (i - 1) * bw + 1, y + h - bh, math.max(1, bw - 2), bh, { fill = mix(c.bg, c.normal, 0.8) })
      end
    end
    for _, f in ipairs({ 100, 1000, 10000 }) do
      local lx = x + math.log(f / 20) / math.log(1000) * w
      g:text(
        lx,
        y + h + 6,
        f >= 1000 and (f / 1000) .. "k" or tostring(f),
        { color = c.faint, size = 11, align = "center" }
      )
    end
  end,
})

-- Commands and menus -------------------------------------------------------------

local function need_part()
  local part = paw.cursor.part()
  if not part then paw.notify("no part selected", "warn") end
  return part
end

paw.command("eq", function()
  local part = need_part()
  if not part then return end
  paw.ui.show("devices")
  open("eq_window", device_on(part, "eq"), { title = "EQ · " .. part.name, width = 900, height = 420 })
end, { desc = "Show the part's equaliser (adding one if it has none): its curve, and in a window, bands to drag" })

paw.command("tuner", function()
  local part = need_part()
  if not part then return end
  paw.ui.show("devices")
  open("tuner_window", device_on(part, "tuner"), { title = "Tuner · " .. part.name, width = 520, height = 300 })
end, { desc = "Tune the part's input: shows its tuner (adding one if it has none)" })

paw.command("loudness", function()
  local master = paw.master
  pcall(paw.cursor.set_part, master)
  paw.ui.show("devices")
  open("meter_window", device_on(master, "meter"), { title = "Loudness · Master", width = 720, height = 380 })
end, { desc = "Measure the mix: the master's loudness meter (adding one if it has none)" })

table.insert(paw.frontend.menus.part, { label = "EQ", command = "eq" })
table.insert(paw.frontend.menus.part, { label = "Tuner", command = "tuner" })
table.insert(paw.frontend.menus.timeline, { label = "Loudness meter", command = "loudness" })

return M
