-- The mix report in a window of a graphical frontend, painted: the loudness
-- and peaks of the mix as bars (with the target marked), each track's peak
-- as a meter, the spectrum as a shape, and the findings to go to. It works
-- on the terminal report's selection (`list_view`), so its keys work here.
local mixdiag = require("mixdiag")
local list = require("mixdiag.view").list_view
local canvas = require("paw.canvas")
local c = canvas.palette

local NAME = "mixdiag_paint"
local HEAD, FOOT, ROW, LABEL = 52, 24, 22, 120
local severity_colour = { error = c.error, warn = c.warn, info = c.select, hint = c.text_3 }

local paint = {
  title = "Mix report",
  modal = true,
  window = false,      -- the terminal's view is the one offered; it names this as `painted`
  hover = nil,         -- the finding under the pointer, and where the pointer is
}
-- Each window looking at it points on its own.
paw.seats.fields("mixdiag.paint", paint, { "hover" })

--- The colour of a meter at `db`, by the window's own steps.
local function meter_colour(db)
  if db > 0 then return c.meter_clip end
  if db > -3 then return c.meter_hot end
  if db > -9 then return c.meter_high end
  if db > -18 then return c.meter_mid end
  return c.meter_low
end

local function number(v, format)
  return v and string.format(format or "%.1f", v) or "–"
end

--- A bar from `low` to `high` dB along `width`: `at` is where `db` falls
--- on it, 0 to 1.
local function fraction(db, low, high)
  return paw.util.clamp((db - low) / (high - low), 0, 1)
end

--- One row of bars: a label, a bar to `db`, the number, and a mark at the
--- target if there is one.
local function bar(g, y, label, db, low, high, text, opts)
  opts = opts or {}
  local w = g.width - LABEL - 78
  g:text(0, y + 3, label, { color = c.text_2, width = LABEL - 8 })
  g:rect(LABEL, y + 4, w, ROW - 10, { fill = c.meter_well, radius = 3 })
  if db then
    g:rect(LABEL, y + 4, math.max(2, w * fraction(db, low, high)), ROW - 10,
      { fill = opts.colour or meter_colour(db), radius = 3 })
  end
  if opts.target then
    local x = LABEL + w * fraction(opts.target, low, high)
    g:line(x, y + 1, x, y + ROW - 3, { color = c.text, width = 1.5 })
  end
  g:text(LABEL + w + 8, y + 3, text, { color = db and c.text or c.text_3, width = 70 })
end

--- The numbers of the whole mix as bars, against the target.
local function draw_loudness(g, result, target, y)
  g:text(0, y, "Loudness", { color = c.text, size = 13, bold = true })
  y = y + 26
  local rows = {
    { "integrated", result.integrated, -40, 0, number(result.integrated) .. " LUFS", target.integrated },
    { "short-term max", result.short_term_max, -40, 0, number(result.short_term_max) .. " LUFS", target.integrated },
    { "momentary max", result.momentary_max, -40, 0, number(result.momentary_max) .. " LUFS" },
    { "true peak", result.true_peak, -40, 3, number(result.true_peak) .. " dBTP", target.true_peak },
    { "sample peak", result.sample_peak, -40, 3, number(result.sample_peak) .. " dBFS" },
    { "RMS", result.rms, -40, 0, number(result.rms) .. " dBFS" },
  }
  for _, row in ipairs(rows) do
    -- Loudness bars are one colour: they are not meters of a level to keep
    -- under full scale.
    local peak = row[1]:find("peak") or row[1] == "RMS"
    bar(g, y, row[1], row[2], row[3], row[4], row[5], { target = row[6], colour = (not peak) and c.select or nil })
    y = y + ROW
  end
  g:text(0, y + 2, string.format("range %s LU    correlation %s    mono loss %s dB", number(result.lra), number(result.correlation, "%.2f"),
    number(result.mono_loss)), { color = c.text_3, size = 11, width = g.width })
  return y + 28
end

--- Each track's peak after its fader, as a meter, over what height is left.
local function draw_tracks(g, result, y, context)
  g:text(0, y, "Tracks (peak)", { color = c.text, size = 13, bold = true })
  y = y + 26
  local room = math.floor((g.height - y) / ROW)
  local shown = 0
  for _, t in ipairs(result.tracks or {}) do
    if shown >= room then
      g:text(0, y + 3, "…", { color = c.text_3 })
      break
    end
    local db = t.peak and t.peak > -150 and t.peak or nil
    bar(g, y, context.track_name(t.id), db, -60, 6, db and (number(db) .. " dB") or "silent")
    y = y + ROW
    shown = shown + 1
  end
  if shown == 0 then g:text(0, y + 3, "no tracks measured", { color = c.text_3 }) end
end

--- Where the energy of the mix lies, by frequency on a log axis: a shape
--- through the middle of each band, its height the band's share in dB.
local function draw_spectrum(g, result)
  g:text(0, 0, "Spectrum", { color = c.text, size = 13, bold = true })
  local bands = result.bands or {}
  local top, h, w = 28, g.height - 28 - 22, g.width
  g:rect(0, top, w, h, { fill = c.meter_well, radius = 4 })
  if #bands == 0 then return end
  local fmin, fmax = 20, 20000
  local function x_of(f) return w * (math.log(math.max(f, fmin)) - math.log(fmin)) / (math.log(fmax) - math.log(fmin)) end
  local function y_of(db) return top + h * (1 - fraction(db, -60, 0)) end
  for _, f in ipairs({ 100, 1000, 10000 }) do
    g:line(x_of(f), top, x_of(f), top + h, { color = c.line_bar })
    g:text(x_of(f) + 3, top + h + 4, f >= 1000 and (f / 1000 .. "k") or tostring(f), { color = c.text_3, size = 10 })
  end
  for _, db in ipairs({ -20, -40 }) do
    g:line(0, y_of(db), w, y_of(db), { color = c.line_sub })
    g:text(3, y_of(db) - 12, db .. " dB", { color = c.text_3, size = 10 })
  end
  local points, base, named = {}, top + h, 0
  for i, band in ipairs(bands) do
    local centre = math.sqrt(math.max(band.low, fmin) * band.high)
    if i == 1 then points[#points + 1] = x_of(fmin); points[#points + 1] = base end
    points[#points + 1] = x_of(centre)
    points[#points + 1] = y_of(band.share)
    if i == #bands then points[#points + 1] = x_of(fmax); points[#points + 1] = base end
    -- A name is left out where the one before it still takes the room.
    local x = x_of(math.max(band.low, fmin)) + 3
    if x >= named then
      g:text(x, top + 4, band.name, { color = c.text_2, size = 10 })
      named = x + 7 * #band.name + 6
    end
  end
  g:poly(points, { fill = "#46b9fe44" })
  g:poly(points, { color = c.select, width = 2 })
end

--- The findings, one to a row; the chosen one is lit.
local function draw_findings(self, g, items)
  g:text(0, 0, string.format("Findings (%d)", #items), { color = c.text, size = 13, bold = true })
  local rows = math.max(1, math.floor((g.height - 26) / ROW))
  if list.at < list.scroll + 1 then list.scroll = list.at - 1 end
  if list.at > list.scroll + rows then list.scroll = list.at - rows end
  list.scroll = paw.util.clamp(list.scroll, 0, math.max(0, #items - rows))
  self.first, self.rows, self.top = list.scroll, rows, 26
  if mixdiag.result and #items == 0 then g:text(0, 28, "no findings", { color = c.text_3 }) end
  for r = 1, rows do
    local i = r + list.scroll
    local item = items[i]
    if not item then break end
    local y = 26 + (r - 1) * ROW
    if i == list.at then
      g:rect(-6, y, g.width + 12, ROW, { fill = c.panel_sel, radius = 3 })
    elseif self.hover and self.hover.item == i then
      g:rect(-6, y, g.width + 12, ROW, { fill = c.panel, radius = 3 })
    end
    g:rect(0, y + 7, 8, 8, { fill = severity_colour[item.severity], radius = 4 })
    g:text(16, y + 4, (item.text:gsub("%s+", " ")), { color = c.text, width = g.width - 20 })
  end
end

--- What the finding under the pointer says in full.
local function draw_tip(self, g, items, width, height)
  local item = self.hover and items[self.hover.item]
  if not item then return end
  local f = item.finding
  local lines = { { f.severity .. "  " .. f.rule, severity_colour[f.severity] }, { f.message, c.text } }
  if f.fix and f.fix ~= "" then lines[3] = { f.fix, c.text_2 } end
  -- Long lines are broken where they pass what fits.
  local fit, wrapped = 64, {}
  for _, line in ipairs(lines) do
    local text = line[1]
    while #text > fit do
      local cut = text:sub(1, fit):match("^.*()%s") or fit
      wrapped[#wrapped + 1] = { text:sub(1, cut), line[2] }
      text = text:sub(cut + 1)
    end
    wrapped[#wrapped + 1] = { text, line[2] }
  end
  local w, h = fit * 6.6 + 20, #wrapped * 17 + 14
  local x = math.max(6, math.min(self.hover.x - w / 2, width - w - 6))
  local y = self.hover.y - h - 10
  if y < HEAD then y = self.hover.y + 22 end
  g:rect(x, y, w, h, { fill = c.card, stroke = c.card_line, radius = 5 })
  for i, line in ipairs(wrapped) do g:text(x + 10, y + 7 + (i - 1) * 17, line[1], { color = line[2] }) end
end

local function draw_head(g, width)
  g:text(14, 8, "Mix report", { color = c.text, size = 14, bold = true })
  local job = mixdiag.job
  if job then
    local done = job.progress or 0
    g:text(110, 10, string.format("measuring the %s… %d%%", job.range.label, math.floor(done * 100 + 0.5)), { color = c.warn })
    g:rect(14, HEAD - 12, width - 28, 4, { fill = c.meter_well, radius = 2 })
    g:rect(14, HEAD - 12, math.max(2, (width - 28) * done), 4, { fill = c.warn, radius = 2 })
  elseif mixdiag.result then
    local range = mixdiag.range_measured and mixdiag.range_measured.label or "mix"
    g:text(110, 10, "the " .. range .. (mixdiag.stale() and ", measured before the last change" or ""),
      { color = mixdiag.stale() and c.warn or c.text_2 })
    g:text(14, 29, mixdiag.summary(mixdiag.result), { color = c.text_2, size = 11 })
  else
    g:text(110, 10, "nothing measured yet", { color = c.text_3 })
    g:text(14, 29, "a measures the song, l the loop, t the cursor's track", { color = c.text_3, size = 11 })
  end
  local target = mixdiag.target()
  local aim = target.integrated and string.format("target %s: %g LUFS, %g dBTP", target.name, target.integrated, target.true_peak or 0)
    or "target: " .. target.name
  g:text(width - 14, 10, aim, { color = c.text_3, size = 11, align = "right", width = width - 140 })
  g:line(0, HEAD - 0.5, width, HEAD - 0.5, { color = c.divider })
end

local function draw_foot(g, width, height)
  local y = height - FOOT
  g:rect(0, y, width, FOOT, { fill = c.panel })
  g:text(12, y + 6, "click a finding to choose it, again to go there   j k move   Enter go   a measure the song   l the loop   t the track   T target   q close",
    { color = c.text_3, size = 11, width = width - 24 })
end

function paint:paint(g, ctx)
  local width, height = ctx.width, ctx.height
  g:rect(0, 0, width, height, { fill = c.surface })
  draw_head(g, width)
  local items = mixdiag.result and mixdiag.items() or {}
  list.items = items
  list.at = paw.util.clamp(list.at, 1, math.max(1, #items))
  local body = height - HEAD - FOOT
  local left_w = math.floor(width * 0.46)
  local right_x, right_w = left_w + 24, width - left_w - 38
  self.right_x, self.right_w, self.body_top = right_x, right_w, HEAD
  if mixdiag.result then
    local side = g:sub(14, HEAD + 12, left_w - 14, body - 12)
    local y = draw_loudness(side, mixdiag.result, mixdiag.target(), 0)
    draw_tracks(side, mixdiag.result, y, mixdiag.context(mixdiag.result, mixdiag.range_measured or { kind = "mix" }))
    local spectrum = math.floor((body - 24) * 0.45)
    draw_spectrum(g:sub(right_x, HEAD + 12, right_w, spectrum), mixdiag.result)
    self.findings_top = HEAD + 12 + spectrum + 16
    draw_findings(self, g:sub(right_x, self.findings_top, right_w, height - FOOT - self.findings_top - 6), items)
  else
    self.findings_top = HEAD + 12
    draw_findings(self, g:sub(right_x, self.findings_top, right_w, body - 12), items)
  end
  draw_foot(g, width, height)
  draw_tip(self, g, items, width, height)
end

--- The finding under a point of the window, or nil.
function paint:item_at(e)
  if not (self.first and e.x >= self.right_x - 6 and e.x < self.right_x + self.right_w + 6) then return nil end
  local r = math.floor((e.y - self.findings_top - self.top) / ROW) + 1
  local item = r >= 1 and r <= self.rows and r + self.first
  return item and list.items[item] and item or nil
end

function paint:pointer(e)
  local item = self:item_at(e)
  if e.kind == "hover" or e.kind == "move" then
    self.hover = item and { item = item, x = e.x, y = e.y } or nil
  elseif e.kind == "wheel" then
    list.at = list.at + ((e.dy or 0) > 0 and -3 or 3)
    self.hover = nil
  elseif e.kind == "down" and e.button == "left" and item then
    -- A click chooses a finding; a click on the one chosen goes there.
    if item == list.at then list:on_key("<CR>") else list.at = item end
  end
end

--- In a terminal that shows pictures the whole view is the painted report;
--- elsewhere it is the report in cells, which this view shares its keys with.
function paint:render(buf, ctx)
  if buf:surface(0, 0, buf.width, buf.height) then return end
  list:render(buf, ctx)
end

function paint:on_key(key)
  -- A window of its own: Escape stays, as in every view, and `q` closes it.
  if key == "<Esc>" then return end
  if key == "q" then return canvas.close(NAME) end
  list:on_key(key)
end

paw.ui.view(NAME, paint)
list.painted = NAME

return paint
