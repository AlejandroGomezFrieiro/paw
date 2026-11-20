-- Plots of time in pixels: what a view draws in a strip (`buf:strip`) to
-- show a curve, so that every curve the program shows looks alike and is
-- sent to the terminal alike. A drawing is made with the painter of
-- `paw.canvas` (`g`), at the strip's size in pixels (`px`, as `buf:strip`
-- gives it), and is cut at the barlines (`g:cut`), snapped to whole
-- cells, so that an edit sends again only the bars it touched.
--
--   plot:strip(0, 0, plot.width, plot.height, { key = "lane:" .. win.id, under = true,
--     draw = function(g, px)
--       paw.plot.curve(g, px, { points = points, from = left, pixels_per_beat = zoom * px.cell.w,
--         lo = 0, hi = 1, color = paw.draw.track_colour(track) })
--     end })
--
-- `M.bars` and `M.wave` draw bars and a waveform the same way, and each
-- has a twin in cells (`M.curve_cells`, `M.bars_cells`, `M.wave_cells`)
-- for where there are no pictures.
--
-- The strip draws no background of its own unless asked (`background`):
-- under the text (`under`), the cells' own backgrounds show through, the
-- selection among them.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local theme = require("paw.theme")
local type contracts = require("paw.contracts")
local type types = require("paw.types")
local type partial = require("paw.partial")
local type CurvesModule = require("paw.curves")
local type DrawModule = require("paw.draw")

-- What this module reads of `paw`, which paw/init.lua makes.
local record Paw is partial.Paw
  curves: CurvesModule
  draw: DrawModule
end
local paw = (_G as {string:Paw}).paw

local type Painter = contracts.Painter
local type Pixels = contracts.StripPixels
local type Buf = contracts.Buf

--- A line of a plot (`paw.plot.lines`): its beat, `x` in pixels from the
--- left, the bar's number on a bar line, and where a drawing may be cut.
local record Line
  beat: number
  x: number
  bar: integer
  cut: number
end

--- Where a value is between the bottom (0) and the top (1) of a plot.
local type Frac = function(value: number): number

--- What `paw.plot.curve` and `paw.plot.curve_cells` take (see `M.curve`).
local record CurveOptions
  points: {CurvesModule.Point}
  from: number
  pixels_per_beat: number
  zoom: number
  frac: Frac
  lo: number
  hi: number
  flat: number
  color: string
  style: contracts.Style
  fill: number | boolean
  width: number
  top: number
  bottom: number
  grid: boolean
  beats: boolean
  guides: boolean
  markers: boolean
  background: string
end

--- An item of `paw.plot.bars`: its beat, its value (0 to 1), its colour
--- (or `style` in cells), and `bright` when it is selected.
local record BarItem
  beat: number
  value: number
  color: string
  style: string
  bright: boolean
end

--- What `paw.plot.bars` and `paw.plot.bars_cells` take.
local record BarsOptions
  items: {BarItem}
  from: number
  pixels_per_beat: number
  zoom: number
  width: number
  top: number
  bottom: number
  color: string
  style: string
end

--- The peaks across a width, `{ min, max, rms }` each (-1 to 1).
local type Peaks = function(n: integer): {{number}}

--- What `paw.plot.wave` and `paw.plot.wave_cells` take: `rms` a colour, or
--- false for no band.
local record WaveOptions
  peaks: Peaks
  color: string
  rms: string | boolean
  clipped: string
  style: string
end

--- Where a beat and a value are in a plot (what `paw.plot.curve` gives).
local type ToX = function(beat: number): number
local type ToY = function(value: number): number

local record M
  type Line = Line
  type CurveOptions = CurveOptions
  type BarItem = BarItem
  type BarsOptions = BarsOptions
  type WaveOptions = WaveOptions
end

local floor, max, min = math.floor, math.max, math.min

local function palette(): theme.Palette return theme.palette end

--- A color `#rrggbb` at `alpha` (0 to 1), as `#rrggbbaa`.
function M.alpha(colour: string, alpha: number): string
  return colour:sub(1, 7) .. string.format("%02x", max(0, min(255, floor(alpha * 255 + 0.5))))
end

--- The bar and beat lines of a plot `w` pixels wide from the beat `from`,
--- at `ppb` pixels for each beat. Each is `{ beat, x, bar }`: `bar` is the
--- number of the bar for a bar line, and `x` is in pixels from the left.
--- `cut` is where paw can cut the drawing for each bar: the nearest edge of
--- a cell of `cell_w` pixels.
function M.lines(w: number, from: number, ppb: number, cell_w?: number): {Line}
  local out: {Line} = {}
  if ppb <= 0 then return out end
  for _, line in ipairs(paw.draw.bar_lines(from, w / ppb + 1)) do
    local x = (line.beat - from) * ppb
    if x >= 0 and x < w then
      out[#out + 1] = {
        beat = line.beat, x = x, bar = line.bar,
        cut = line.bar and cell_w and floor(x / cell_w + 0.5) * cell_w or nil,
      }
    end
  end
  return out
end

--- Draw a curve over time in a strip: its grid, the area under it, the
--- line, and its points. `px` is the strip's size as `buf:strip` gives it
--- (`w`, `h`, `cell`). `opts`:
---   points            `{ beat, value, shape, tension }` each, in order, as `paw.curves` has them
---   from              the beat at the left edge
---   pixels_per_beat   the zoom
---   frac              `frac(value)` from 0 (bottom) to 1 (top); else `lo` and `hi`
---   flat              the value shown when there are no points (else nothing is)
---   color             the line's colour, `#rrggbb` (the theme's `dim` by default):
---                     a track's own is `paw.draw.track_colour(track)`
---   fill              how opaque the area under the line is, 0 to 1 (0.16); false for none
---   width             the line's width in pixels (1.5)
---   top, bottom       pixels kept clear above 1 and below 0 (2 each)
---   grid              bars (and beats, when `beats`) as lines, true by default
---   beats             beat lines too (when beats are at least two cells apart, by default)
---   guides            faint lines at a quarter, half and three quarters (true)
---   markers           a small mark at each point (true)
---   background        a colour to fill the strip with first (none: the cells show)
--- Returns `x(beat)` and `y(value)`, where in the strip a beat and a value are.
function M.curve(g: Painter, px: Pixels, opts: CurveOptions): ToX, ToY
  local P = palette()
  local W, H = px.w, px.h
  local cw = px.cell and px.cell.w or 8
  local from, ppb = opts.from or 0, opts.pixels_per_beat or cw
  local lo, hi = opts.lo or 0, opts.hi or 1
  local frac = opts.frac or function(v: number): number return (v - lo) / ((hi - lo) ~= 0 and (hi - lo) or 1) end
  local top, bottom = opts.top or 2, opts.bottom or 2
  local function X(beat: number): number return (beat - from) * ppb end
  local function Y(v: number): number return top + (1 - max(0, min(1, frac(v)))) * (H - top - bottom) end
  if opts.background then g:rect(0, 0, W, H, { fill = opts.background }) end

  -- The grid, and where the drawing is cut: at each bar, on a cell's edge.
  local lines = M.lines(W, from, ppb, cw)
  local edges: {number} = { 0 }
  for _, line in ipairs(lines) do
    if line.cut and line.cut > edges[#edges] and line.cut < W then
      edges[#edges + 1] = line.cut
      g:cut(line.cut, 0, H)
    end
  end
  edges[#edges + 1] = W
  if opts.grid ~= false then
    local beats = opts.beats
    if beats == nil then beats = ppb >= 2 * cw end
    for _, line in ipairs(lines) do
      if line.bar or beats then
        g:rect(floor(line.x), 0, 1, H, { fill = line.bar and P.line_hi or P.line_beat })
      end
    end
  end
  if opts.guides ~= false then
    for i = 1, 3 do
      g:rect(0, floor(top + i * (H - top - bottom) / 4), W, 1, { fill = P.line })
    end
  end

  local points = opts.points or {}
  if #points == 0 and opts.flat == nil then return X, Y end
  local color = opts.color or P.dim
  local value_at = paw.curves.value_at
  local function value(beat: number): number return value_at(points, beat) or opts.flat end

  -- The line and the area under it, one stretch between two cuts at a
  -- time, sampled once a pixel: a stretch changes only with its bar.
  local fill = opts.fill == nil and 0.16 or opts.fill
  for i = 1, #edges - 1 do
    local a, b = edges[i], edges[i + 1]
    local line: {number} = {}
    for x = a, b do
      line[#line + 1] = x
      line[#line + 1] = Y(value(from + x / ppb))
    end
    if fill is number and fill > 0 then
      local area: {number} = { a, H }
      for k = 1, #line do area[#area + 1] = line[k] end
      area[#area + 1] = b
      area[#area + 1] = H
      g:poly(area, { fill = M.alpha(color, fill) })
    end
    g:poly(line, { color = color, width = opts.width or 1.5 })
  end

  if opts.markers ~= false then
    for _, q in ipairs(points) do
      local x, y = X(q.beat), Y(q.value)
      if x >= -4 and x <= W + 4 then
        local shape = q.shape or "linear"
        g:rect(x - 2.5, y - 2.5, 5, 5, {
          fill = P.bright, stroke = color, width = 1, radius = shape == "smooth" and 2.5 or shape == "hold" and 0 or 1,
        })
      end
    end
  end
  return X, Y
end

--- The part of a strip to draw, in pixels from its left. This is the part
--- that shows (`px.view`, all of it when all of it shows) and the width of
--- a piece on each side. It is in whole pieces of `step` pixels from the
--- left edge of the strip. So a piece is the same at each scroll
--- position. Returns the first and the last pixel.
function M.span(px: Pixels, step: number): number, number
  local v: types.Rect = px.view or { x = 0, w = px.w }
  local margin = 24 * (px.cell and px.cell.w or 8)
  local a = max(0, floor((v.x - margin) / step) * step)
  local b = min(px.w, (floor((v.x + v.w + margin) / step) + 1) * step)
  return a, b
end

--- Bars over time in a strip, one for each of `opts.items`, `{ beat,
--- value, color, bright }`. `value` goes from 0 at the bottom to 1 at the
--- top, and `bright` is for a selected item. Each bar is `opts.width`
--- pixels wide (3), from the bottom, with a head. `from` and
--- `pixels_per_beat` are as for `M.curve`. `color` is for the bars that
--- have no color.
function M.bars(g: Painter, px: Pixels, opts: BarsOptions)
  local P = palette()
  local H = px.h
  local from, ppb = opts.from or 0, opts.pixels_per_beat or 8
  local width = opts.width or 3
  local top, bottom = opts.top or 2, opts.bottom or 0
  for _, item in ipairs(opts.items or {}) do
    local x = floor((item.beat - from) * ppb)
    if x >= -width and x <= px.w then
      local v = max(0, min(1, item.value))
      local y = floor(top + (1 - v) * (H - top - bottom))
      local colour = item.bright and P.bright or item.color or opts.color or P.dim
      g:rect(x, y, width, H - bottom - y, { fill = M.alpha(colour, 0.55) })
      g:rect(x, y, width, 2, { fill = colour })
    end
  end
end

--- A waveform in a strip. For each pixel across, it shows the lowest to the
--- highest sample around the middle, with its RMS as a brighter band in it.
--- A column that reaches full scale is in the clip color. `opts`:
---   peaks       `peaks(n)`: `n` `{ min, max, rms }` (-1 to 1) across the
---               whole strip, as `api.clip_peaks` gives them; `n` is the
---               strip's width in pixels, at most 65536
---   color       the wave's colour (the theme's `dim`)
---   rms         the RMS band's colour (the wave's, brighter); false for none
---   clipped     the colour of a column at full scale (the theme's `red`)
--- Heights obey `paw.opt.wave_scale`, as the cells do.
function M.wave(g: Painter, px: Pixels, opts: WaveOptions)
  local P = palette()
  local W, H = px.w, px.h
  local n = min(floor(W), 65536)
  if n < 1 then return end
  local peaks = opts.peaks(n) or {}
  if #peaks == 0 then return end
  local reach = paw.draw.wave_reach
  local mid, half = H / 2, H / 2 - 1
  local color = opts.color or P.dim
  local rms = opts.rms
  if rms == nil then rms = paw.draw.mix(color, "#ffffff", 0.35) end
  local clipped = opts.clipped or P.red
  local function at(x: number): {number} return peaks[min(#peaks, floor(x * #peaks / W) + 1)] end
  local function y_of(v: number): number return mid - (v < 0 and -1 or 1) * reach(v) * half end
  -- A stretch of eight cells at a time, so that one scrolled in is drawn
  -- the same as before.
  local step = 8 * (px.cell and px.cell.w or 8)
  local a, b = M.span(px, step)
  for s = a, b - 1, step do
    local e = min(b, s + step)
    local upper: {number} = {}
    local lower: {number} = {}
    local band_up: {number} = {}
    local band_down: {number} = {}
    local run: number
    for x = s, e do
      local p = at(min(x, W - 1))
      if p then
        upper[#upper + 1], upper[#upper + 2] = x, min(y_of(p[2]), mid - 0.5)
        lower[#lower + 1], lower[#lower + 2] = x, max(y_of(p[1]), mid + 0.5)
        local r = p[3] or 0
        band_up[#band_up + 1], band_up[#band_up + 2] = x, mid - reach(r) * half
        band_down[#band_down + 1], band_down[#band_down + 2] = x, mid + reach(r) * half
        local full = p[2] >= 0.999 or p[1] <= -0.999
        if full and x < e then
          run = run or x
        elseif run then
          g:rect(run, 0, x - run, H, { fill = M.alpha(clipped, 0.8) })
          run = nil
        end
      end
    end
    if run then g:rect(run, 0, e - run, H, { fill = M.alpha(clipped, 0.8) }) end
    local function shape(top: {number}, bottom: {number}): {number}
      local out: {number} = {}
      for i = 1, #top do out[i] = top[i] end
      for i = #bottom - 1, 1, -2 do out[#out + 1], out[#out + 2] = bottom[i], bottom[i + 1] end
      return out
    end
    if #upper >= 4 then
      g:poly(shape(upper, lower), { fill = color })
      if rms is string then g:poly(shape(band_up, band_down), { fill = rms }) end
    end
  end
end

-- Twins in cells -------------------------------------------------------------------
--
-- What a view draws where a strip cannot be shown: the same data, in
-- cells, as the views draw them (`paw.draw`). `buf` is the area the strip
-- would have taken, and the options are the pixel version's, with `zoom`
-- (cells a beat) for `pixels_per_beat` and `style` for the colour.

--- `M.curve` in cells: a connected line of sextants (`paw.opt.curve_glyphs`).
function M.curve_cells(buf: Buf, opts: CurveOptions)
  local points = opts.points or {}
  if #points == 0 and opts.flat == nil then return end
  local lo, hi = opts.lo or 0, opts.hi or 1
  local frac = opts.frac or function(v: number): number return (v - lo) / ((hi - lo) ~= 0 and (hi - lo) or 1) end
  local from, zoom = opts.from or 0, opts.zoom or 1
  local value_at = paw.curves.value_at
  paw.draw.curve(buf, 0, buf.height, function(i: integer): number
    local v = value_at(points, from + (i + 0.5) / (2 * zoom)) or opts.flat
    return v and frac(v)
  end, opts.style)
end

--- `M.bars` in cells: a column of eighth blocks for each item.
function M.bars_cells(buf: Buf, opts: BarsOptions)
  local eighths = paw.draw.g.eighths
  local rows = buf.height
  local from, zoom = opts.from or 0, opts.zoom or 1
  for _, item in ipairs(opts.items or {}) do
    local x = floor((item.beat - from) * zoom + 0.5)
    if x >= 0 and x < buf.width then
      local level = max(0, min(1, item.value)) * rows * 8
      local style = item.bright and "Bright" or item.style or opts.style
      for row = 0, rows - 1 do
        local amount = level - (rows - 1 - row) * 8
        if amount >= 1 then buf:text(x, row, eighths[min(8, floor(amount))], style) end
      end
    end
  end
end

-- Styles for the cells of a waveform that `paw.draw.waveform` marks.
local wave_styles: {string:string} = { flip = "ClipWaveFlip", clip = "ClipWaveClip", clipflip = "ClipWaveClipFlip" }

--- `M.wave` in cells: each column from its lowest to its highest sample in
--- eighth blocks (`paw.draw.waveform`), a column at full scale in red.
--- `opts.peaks(n)` is asked for one a column.
function M.wave_cells(buf: Buf, opts: WaveOptions)
  local _, runs = paw.draw.waveform(opts.peaks(buf.width) or {}, buf.height)
  for row, list in ipairs(runs) do
    for _, run in ipairs(list) do buf:text(run.column, row - 1, run.text, wave_styles[run.mark] or opts.style) end
  end
end

return M
