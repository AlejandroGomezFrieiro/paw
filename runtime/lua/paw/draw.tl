-- What views are drawn from: shades of a track's colour, the characters,
-- meters, sliders, small piano rolls and curves. Views and extensions share
-- these so that everything on screen looks like part of the same program.
--
--   local hue = paw.draw.track_hue(track, index)   -- highlight groups in the track's colour
--   local g = paw.draw.g                           -- the characters, ASCII under `paw.opt.ascii`
--   buf:text(0, 0, g.stripe, hue.fg)
--   paw.draw.meter(buf, x, y, width, peak)
--   paw.draw.slider(buf, x, y, width, fraction)
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local theme = require("paw.theme")
local options = require("paw.options")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type objects = require("paw.objects")
local type GroupsModule = require("paw.groups")
local type MusicModule = require("paw.music")
local type TempoModule = require("paw.tempo")
local type UtilModule = require("paw.util")

-- What this module reads of `paw`, which paw/init.lua makes.
-- paw/ui.tl names this module's types, so this one declares only the part
-- of it that it calls.
local record Ui
  hl: function(name: string, def: string | types.CellStyle)
end
local record Paw is partial.Paw
  ui: Ui
  groups: GroupsModule
  music: MusicModule
  tempo: TempoModule
  time: objects.Time
  util: UtilModule
end
local paw = (_G as {string: Paw}).paw
local opt = options.opt
local events = require("paw.events")
local kernel = require("paw.events.kernel")

local type Buf = contracts.Buf
local type Style = contracts.Style

--- The highlight groups in the shades of one colour (`paw.draw.hue`).
local record Hue
  fg: string
  title: string
  body: string
  title_cur: string
  body_cur: string
  title_off: string
  body_off: string
  lane_sel: string
  note: string
  note_soft: string
  note_faint: string
  pill: string
  plate: string
end

--- The characters views draw with, by what they are for (`paw.draw.g`).
local type Glyphs = contracts.Glyphs

--- Glyphs as a table of names, to copy.
local type GlyphTable = {string: string | {string}}

--- A highlight definition: a group's name, or colours and attributes.
local type Def = string | types.CellStyle

--- A bar line (`bar`, from 1) or a beat inside a bar, at its beat.
local record BarLine
  beat: number
  bar: integer
end

--- A line of a ruler (`paw.draw.beats`): `x` in columns, `bar` true on a
--- bar, `beat` from the roll's beat 0.
local record RulerLine
  x: integer
  bar: boolean
  beat: number
end

--- A run of cells of one mark in a row of a waveform (`paw.draw.waveform`):
--- from `column` (from 0), its text, and its mark ("flip", "clip",
--- "clipflip", or nil). `cells` holds the text while it is made.
local record WaveRun
  column: integer
  text: string
  mark: string
  cells: {string}
end

--- A chip of `paw.draw.chips`: its letter, whether it is on, and its group
--- when on.
local type Chip = {string, boolean, string}

--- A key and what it does, for a line of hints: `{ "o", "new track" }`.
local type KeyHint = {string, string}

--- The height of a curve at a point (two a column), 0 to 1, or nil.
local type Height = function(i: integer): number

--- The row of a line at a sample (two a column), from the top, or nil.
local type Row = function(sx: integer): integer

--- Both sets of characters.
local record GlyphSets
  unicode: Glyphs
  ascii: Glyphs
end

local record M
  type Hue = Hue
  type Glyphs = Glyphs
  type BarLine = BarLine
  type RulerLine = RulerLine
  type WaveRun = WaveRun
  type Chip = Chip
  type KeyHint = KeyHint
  --- The characters views draw with now.
  g: Glyphs
  glyphs: GlyphSets
end

local function rgb(hex: string): integer, integer, integer
  return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

--- A color between two colors: `t` 0 gives `a`, 1 gives `b`.
function M.mix(a: string, b: string, t: number): string
  local r1, g1, b1 = rgb(a)
  local r2, g2, b2 = rgb(b)
  local function ch(x: integer, y: integer): integer
    return math.floor(x + (y - x) * t + 0.5)
  end
  return string.format("#%02x%02x%02x", ch(r1, r2), ch(g1, g2), ch(b1, b2))
end

-- Colours on terminals without 24-bit colour ----------------------------------

local cube: {integer} = {0, 95, 135, 175, 215, 255}

local function nearest_level(v: integer): integer
  local best, at = math.huge, 1
  for i, level in ipairs(cube) do
    if math.abs(level - v) < best then
      best, at = math.abs(level - v), i
    end
  end
  return at - 1
end

--- The nearest of the 256 colors to `#rrggbb`, from the 6x6x6 cube (16 to
--- 231) or the grays (232 to 255). A color with little hue gets a gray.
--- Returns its index and the color that the index shows.
function M.nearest256(hex: string): integer, string
  local r, g, b = rgb(hex)
  local ri, gi, bi = nearest_level(r), nearest_level(g), nearest_level(b)
  local spread = math.max(r, g, b) - math.min(r, g, b)
  if spread > 28 and ri == gi and gi == bi then
    -- The nearest point is a grey, but the colour has a hue: take the
    -- nearest of the points around it that keeps one.
    local function around(v: integer): {integer}
      local lo = 1
      for i, level in ipairs(cube) do
        if level <= v then
          lo = i
        end
      end
      return {lo - 1, math.min(5, lo)}
    end
    local best: {number}
    for _, a in ipairs(around(r)) do
      for _, b2 in ipairs(around(g)) do
        for _, c3 in ipairs(around(b)) do
          if not (a == b2 and b2 == c3) then
            local d = (cube[a + 1] - r) ^ 2 + (cube[b2 + 1] - g) ^ 2 + (cube[c3 + 1] - b) ^ 2
            if not best or d < best[1] then
              best = {d, a, b2, c3}
            end
          end
        end
      end
    end
    if best then
      ri, gi, bi = best[2] as integer, best[3] as integer, best[4] as integer
    end
  end
  local cr, cg, cb = cube[ri + 1], cube[gi + 1], cube[bi + 1]
  local index = 16 + 36 * ri + 6 * gi + bi
  local dist = (cr - r) ^ 2 + (cg - g) ^ 2 + (cb - b) ^ 2
  -- The greys run from 8 to 238 in steps of 10.
  local grey = math.floor(((r + g + b) / 3 - 8) / 10 + 0.5)
  grey = math.max(0, math.min(23, grey))
  local level = 8 + grey * 10
  local gdist = (level - r) ^ 2 + (level - g) ^ 2 + (level - b) ^ 2
  -- A colour with little hue in it is a grey: the cube's nearest point would
  -- give it a tint it does not have.
  if spread <= 28 or (gdist < dist and ri == gi and gi == bi) then
    return 232 + grey, string.format("#%02x%02x%02x", level, level, level)
  end
  return index, string.format("#%02x%02x%02x", cr, cg, cb)
end

--- True if the terminal shows 24-bit color. `paw.opt.termcolors` is "true"
--- or "256". With "auto" (the default), the environment tells: COLORTERM of
--- truecolor or 24bit, or a TERM that ends in -direct.
function M.truecolor(): boolean
  local want = tostring(opt.termcolors or "auto")
  if want == "true" or want == "truecolor" or want == "24bit" then
    return true
  end
  if want == "256" then
    return false
  end
  local colorterm = (os.getenv("COLORTERM") or ""):lower()
  if colorterm == "truecolor" or colorterm == "24bit" then
    return true
  end
  return (os.getenv("TERM") or ""):match("%-direct$") ~= nil
end

--- A highlight definition as this terminal can show it. On a terminal
--- without 24-bit color, each `#rrggbb` becomes the nearest of the 256.
function M.term_def(def: Def, truecolor: boolean): Def
  if truecolor or not (def is types.CellStyle) then
    return def
  end
  local out: {string: types.Colour | boolean} = {}
  for k, v in pairs(def as {string: types.Colour | boolean}) do
    if (k == "fg" or k == "bg") and v is string and v:match("^#%x%x%x%x%x%x$") then
      out[k] = M.nearest256(v)
    else
      out[k] = v
    end
  end
  return out as types.CellStyle
end

-- Characters ------------------------------------------------------------------

-- A beat begins at a cell's left edge: that is where a clip or a note that
-- starts on it begins to be drawn. So the lines and ticks of a timeline are
-- characters that sit on that edge, not ones centred in the cell, which
-- would stand half a cell to the right of everything that starts there.
local unicode: Glyphs = {
  rule = "│",
  bar = "▏",
  beat = "▏",
  step = "▏",
  tick = "▏",
  cap = "▼",
  playhead = "▏",
  loop_in = "▕",
  loop_out = "▕",
  clip_start = "▏",
  nest = "⧉ ",
  link = "≡",
  punch_in = "▕",
  punch_out = "▕",
  meter_full = "━",
  meter_half = "╸",
  meter_off = "─",
  peak = "▔",
  upper = "▀",
  lower = "▄",
  full = "█",
  slider_on = "━",
  knob = "●",
  slider_off = "─",
  pan_rail = "─",
  pan_mark = "┃",
  fader = "━",
  fader_rail = "│",
  zero = "╪",
  point = "◆",
  open = "▾",
  closed = "▸",
  stripe = "▌",
  stripe_sel = "█",
  send = "↗",
  out = "→",
  chain = "›",
  sep = "│",
  dot = "·",
  play = "▶",
  stop = "■",
  rec = "●",
  modified = "●",
  bypass = "◌",
  on = "●",
  ellipsis = "…",
  cursor = "▶",
  warn = "!",
  error = "✗",
  hairline = "▏",
  strip_sep = "┃",
  tl = "╭",
  tr = "╮",
  bl = "╰",
  br = "╯",
  h = "─",
  v = "│",
  mark = "▌",
  move_up = "↑",
  move_down = "↓",
  remove = "×",
  editor = "⧉",
  eighths = {"▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"},
}
local ascii: Glyphs = {
  rule = "|",
  bar = "|",
  beat = ":",
  step = ".",
  tick = ".",
  cap = "v",
  playhead = "|",
  loop_in = "[",
  loop_out = "]",
  clip_start = "|",
  nest = "& ",
  link = "=",
  punch_in = "{",
  punch_out = "}",
  meter_full = "=",
  meter_half = "-",
  meter_off = ".",
  peak = "-",
  upper = "'",
  lower = ".",
  full = ":",
  slider_on = "=",
  knob = "o",
  slider_off = "-",
  pan_rail = "-",
  pan_mark = "|",
  fader = "=",
  fader_rail = "|",
  zero = "+",
  point = "*",
  open = "v",
  closed = ">",
  stripe = "|",
  stripe_sel = "#",
  send = "^",
  out = ">",
  chain = ">",
  sep = "|",
  dot = ".",
  play = ">",
  stop = "#",
  rec = "*",
  modified = "*",
  bypass = "o",
  on = "*",
  ellipsis = "~",
  cursor = ">",
  warn = "!",
  error = "x",
  hairline = "|",
  strip_sep = "|",
  tl = "+",
  tr = "+",
  bl = "+",
  br = "+",
  h = "-",
  v = "|",
  mark = "|",
  move_up = "^",
  move_down = "v",
  remove = "x",
  editor = "#",
  eighths = {".", ".", "-", "-", "=", "=", "#", "#"},
}

--- The characters views draw with, by what they are for. The same table
--- holds plain ASCII ones while `paw.opt.ascii` is on.
M.g = {}
M.glyphs = {unicode = unicode, ascii = ascii}

--- Take the glyphs `paw.opt.ascii` asks for into `paw.draw.g`.
function M.use_glyphs()
  local from = opt.ascii and ascii or unicode
  local into = M.g as GlyphTable
  for k, v in pairs(from as GlyphTable) do
    into[k] = v
  end
end

-- Shades of a colour ----------------------------------------------------------

local hues: {string: Hue} = {}
local stereo_groups: {string: boolean} = {}

--- Highlight groups in the shades of one color (`#rrggbb`), made the first
--- time that a caller asks for the color:
---   fg                  the colour itself, on whatever is behind it
---   title, body         a clip's name row and the rows under it
---   title_cur, body_cur the same for the clip under the cursor (or chosen)
---   title_off, body_off the same for a muted clip
---   lane_sel            the background of the selected track's lane
---   note, note_soft, note_faint   notes, loud to quiet
---   pill                dark text on the colour
---   plate               a name plate: light text on a deep shade
function M.hue(colour: string): Hue
  local known = hues[colour]
  if known then
    return known
  end
  if not (type(colour) == "string" and colour:match("^#%x%x%x%x%x%x$")) then
    return M.hue(theme.hues[1])
  end
  local c, mix = theme.palette, M.mix
  local key = colour:sub(2)
  local dark = mix(colour, "#000000", 0.78)
  local defs: {string: types.CellStyle} = {
    fg = {fg = colour},
    title = {fg = mix(colour, "#ffffff", 0.85), bg = mix(c.bg, colour, 0.55), bold = true},
    body = {fg = mix(c.bg, colour, 0.75), bg = mix(c.bg, colour, 0.20)},
    title_cur = {fg = dark, bg = colour, bold = true},
    body_cur = {fg = mix(colour, "#ffffff", 0.25), bg = mix(c.bg, colour, 0.34)},
    title_off = {fg = c.dim, bg = mix(c.bg, colour, 0.10), italic = true},
    body_off = {fg = mix(c.bg, colour, 0.30), bg = mix(c.bg, colour, 0.06)},
    lane_sel = {fg = c.line_hi, bg = mix(c.bg, colour, 0.06)},
    note = {fg = dark, bg = colour},
    note_soft = {fg = dark, bg = mix(c.bg, colour, 0.82)},
    note_faint = {fg = dark, bg = mix(c.bg, colour, 0.6)},
    pill = {fg = dark, bg = colour, bold = true},
    plate = {fg = mix(colour, "#ffffff", 0.85), bg = mix(c.bg, colour, 0.55), bold = true},
  }
  local names: {string: string} = {}
  for name, def in pairs(defs) do
    names[name] = "Hue_" .. name .. "_" .. key
    paw.ui.hl(names[name], def)
  end
  local hue = names as Hue
  hues[colour] = hue
  return hue
end

--- Forget the shades made until now. Call it after the palette changes.
function M.reset()
  hues = {}
  stereo_groups = {}
end

--- The color of a track: its own color if it has one. If not, a color of
--- the theme, by the place of the track in the track list.
function M.track_colour(track: types.Track, index?: integer): string
  if track.color and track.color:match("^#%x%x%x%x%x%x$") then
    return track.color
  end
  if track.master then
    return theme.palette.dim
  end
  -- A member of a group is in its group's colour, so a section reads as one.
  local group = track.id and paw.groups and paw.groups.of(track.id)
  if group then
    return M.track_colour(api.track_get(group))
  end
  -- By its place in the list, which folding a group away does not change.
  return theme.hues[((track.index or index or 1) - 1) % #theme.hues + 1]
end

--- The hue of the color of a track, from 0 to 360.
function M.track_hue(track: types.Track, index?: integer): Hue
  return M.hue(M.track_colour(track, index))
end

--- The shade of a note by how hard it is played.
function M.note_style(hue: Hue, velocity: number): string
  if velocity >= 90 then
    return hue.note
  end
  if velocity >= 50 then
    return hue.note_soft
  end
  return hue.note_faint
end

-- Meters and controls ---------------------------------------------------------

local function meter_style(at: number): string
  return at > 0.92 and "MeterHigh" or at > 0.75 and "MeterMid" or "MeterLow"
end

--- How far up a meter a linear peak reaches, from 0 to 1 over 60 dB.
function M.level(peak: number): number
  local db = 20 * math.log10(math.max(peak, 1e-6))
  return paw.util.clamp((db + 60) / 60, 0, 1)
end

--- Where on a meter `width` cells long a level in dB falls, from 0.
function M.db_cell(db: number, width: integer): integer
  return math.floor(paw.util.clamp((db + 60) / 60, 0, 1) * (width - 1) + 0.5)
end

--- A level meter `width` cells wide for a linear peak: a thin rail, lit
--- from the left, green then yellow then red. With `hold` (a linear peak),
--- the loudest of late is marked.
function M.meter(buf: Buf, x: integer, y: integer, width: integer, peak: number, hold?: number)
  local g = M.g
  local filled = M.level(peak) * width
  for cell = 0, width - 1 do
    local amount = filled - cell
    if amount >= 0.75 then
      buf:text(x + cell, y, g.meter_full, meter_style((cell + 1) / width))
    elseif amount >= 0.25 then
      buf:text(x + cell, y, g.meter_half, meter_style((cell + 1) / width))
    else
      buf:text(x + cell, y, g.meter_off, "MeterOff")
    end
  end
  if hold and hold > 1e-5 then
    local at = math.min(width - 1, math.floor(M.level(hold) * width))
    if at >= math.floor(filled) then
      buf:text(x + at, y, g.meter_half, "MeterPeak")
    end
  end
end

--- What `meter` shows for these values in `width` cells, as a text: the
--- cells lit full and half, and the cell of the peak held (-1: none).
function M.meter_shown(width: integer, peak: number, hold?: number): string
  local filled = M.level(peak) * width
  local full = math.max(0, math.min(width, math.floor(filled - 0.75) + 1))
  local half = math.max(0, math.min(width, math.floor(filled - 0.25) + 1))
  local mark = -1
  if hold and hold > 1e-5 then
    local at = math.min(width - 1, math.floor(M.level(hold) * width))
    if at >= math.floor(filled) then
      -- The mark covers its cell, and the cells after it are off.
      mark = at
      full, half = math.min(full, at), math.min(half, at)
    end
  end
  return full .. " " .. half .. " " .. mark
end

--- A level meter `height` cells tall, lit from the bottom, with the peak
--- held (`hold`, linear) marked by a line over its cell.
function M.vmeter(buf: Buf, x: integer, y: integer, height: integer, peak: number, hold?: number)
  local g = M.g
  local filled = M.level(peak) * height
  -- The unlit part in one go: most of a meter, most of the time.
  local lit = math.min(height, math.ceil(filled - 0.06))
  local off = height - math.max(0, lit)
  if off > 0 then
    buf:fill(x, y, 1, off, g.v, "MeterOff")
  end
  local hold_row = hold and hold > 1e-5 and math.min(height - 1, math.floor(M.level(hold) * height)) or nil
  for row = 0, height - 1 do
    local from_bottom = height - 1 - row
    local amount = filled - from_bottom
    local style = meter_style((from_bottom + 1) / height)
    if amount >= 1 then
      buf:text(x, y + row, g.full, style)
    elseif amount > 0.06 then
      buf:text(x, y + row, g.eighths[math.max(1, math.floor(amount * 8 + 0.5))], style)
    elseif hold_row == from_bottom then
      buf:text(x, y + row, g.peak, "MeterPeak")
    end
  end
end

--- The two sides of a stereo level in one row that is `width` cells wide.
--- The left side is in the upper half of each cell, the right in the lower.
function M.stereo_meter(buf: Buf, x: integer, y: integer, width: integer, left: number, right: number)
  local g = M.g
  if opt.ascii then
    M.meter(buf, x, y, width, math.max(left, right))
    return
  end
  local p = theme.palette
  local colours: {string: string} = {
    off = p.bg_hl, MeterLow = p.meter_low, MeterMid = p.meter_mid, MeterHigh = p.meter_high
  }
  local lf, rf = M.level(left) * width, M.level(right) * width
  for cell = 0, width - 1 do
    local style = meter_style((cell + 1) / width)
    local up = lf - cell >= 0.5 and style or "off"
    local down = rf - cell >= 0.5 and style or "off"
    local name = "MeterLR_" .. up .. "_" .. down
    if not stereo_groups[name] then
      stereo_groups[name] = true
      paw.ui.hl(name, {fg = colours[up], bg = colours[down]})
    end
    buf:text(x + cell, y, g.upper, name)
  end
end

--- What `stereo_meter` shows for these values in `width` cells, as a
--- text: the cells lit on each side.
function M.stereo_meter_shown(width: integer, left: number, right: number): string
  if opt.ascii then
    return M.meter_shown(width, math.max(left, right))
  end
  local function lit(level: number): integer
    return math.max(0, math.min(width, math.floor(M.level(level) * width - 0.5) + 1))
  end
  return lit(left) .. " " .. lit(right)
end

local record Held
  peak: number
  time: number
end
local held: {string: Held} = {}
--- Peaks held for some time, by key. `hold(key, peak)` gives the loudest
--- peak of the last two seconds, which falls after that time.
function M.hold(key: string, peak: number): number
  local now = api.now()
  local h = held[key]
  if not h then
    h = {peak = peak, time = now}
    held[key] = h
  elseif peak >= h.peak or now - h.time > 2000 then
    h.peak, h.time = peak, now
  end
  return h.peak
end

-- The tracks whose meters reached full scale since their light was put out.
-- A light that came on in the last take is not news in the next: they go
-- out when the transport starts.
local clipped: {integer: boolean} = {}
events.on(kernel.transport_play, function() clipped = {} end)

--- The meter of a track as the mixer shows it, in a terminal and in a
--- window (`scene.live`). It gives the two sides and the loudest recent
--- peak. It also tells if the track reached full scale after the last
--- `clear_peak` for it.
function M.track_peak(id: integer): number, number, number, boolean
  local left, right = api.track_meter(id)
  local loudest = math.max(left, right)
  if loudest >= 0.9999 then
    clipped[id] = true
  end
  return left, right, M.hold("mix" .. id, loudest), clipped[id] == true
end

-- The meters' floor: a level below -60 dB lights no part of a meter.
local floor = 0.001

--- True while a track meter drawn lately (`track_peak`) still shows a
--- level: it is not at rest yet.
function M.meters_falling(): boolean
  for key in pairs(held) do
    local id = tonumber(key:match("^mix(%d+)$"))
    if id then
      local ok, left, right = pcall(api.track_meter, id as integer) as (boolean, number, number)
      if ok and math.max(left or 0, right or 0) >= floor then
        return true
      end
    end
  end
  return false
end

--- Put out a track's clip light and let its loudest of late fall.
function M.clear_peak(id: integer)
  clipped[id] = nil
  held["mix" .. id] = nil
end

--- A slider `width` cells wide with its knob `fraction` of the way along.
function M.slider(buf: Buf, x: integer, y: integer, width: integer, fraction: number, on?: Style, off?: Style)
  local g = M.g
  local at = math.floor(paw.util.clamp(fraction, 0, 1) * (width - 1) + 0.5)
  if at > 0 then
    buf:text(x, y, string.rep(g.slider_on, at), on or "ParamBar")
  end
  buf:text(x + at, y, g.knob, on or "ParamBar")
  if at < width - 1 then
    buf:text(x + at + 1, y, string.rep(g.slider_off, width - 1 - at), off or "ParamBarOff")
  end
end

--- A pan from -1 to 1 as a bar that is `width` cells wide (an odd number
--- is best). It is a rail with a mark at the position of the sound,
--- `───┃───` in the middle.
function M.pan(buf: Buf, x: integer, y: integer, width: integer, pan: number, style?: Style)
  local g = M.g
  local at = math.floor((paw.util.clamp(pan, -1, 1) + 1) / 2 * (width - 1) + 0.5)
  buf:text(x, y, string.rep(g.pan_rail, width), "FaderTrack")
  buf:text(x + at, y, g.pan_mark, style or (math.abs(pan) < 0.005 and "TrackInfo" or "Bright"))
end

--- Where a pan from -1 to 1 points, in a few cells: `L30`, `C`, `R100`.
function M.pan_text(pan: number): string
  local amount = math.floor(math.abs(pan) * 100 + 0.5)
  if amount == 0 then
    return "C"
  end
  return (pan < 0 and "L" or "R") .. amount
end

--- A volume in dB as few cells as it can: `-4.0`, `-inf`, `+2.5`.
function M.db_text(db: number): string
  if db <= -100 then
    return "-inf"
  end
  return string.format(db > 0.05 and "+%.1f" or "%.1f", db)
end

--- Small on/off marks side by side, each a letter on a cell of its own:
--- `chips(buf, x, y, { { "M", on, "Mute" }, ... }, gap)`. Returns the columns used.
function M.chips(buf: Buf, x: integer, y: integer, list: {Chip}, gap?: integer): integer
  gap = gap or 1
  local at = x
  for i, chip in ipairs(list) do
    at = at + buf:text(at, y, chip[1], chip[2] and chip[3] or "FlagOff")
    if i < #list then
      at = at + gap
    end
  end
  return at - x
end

-- Pictures inside clips -------------------------------------------------------

--- Notes as a small piano roll of `rows` text rows, each `width` columns.
--- A row holds two pitches, drawn with half blocks. `notes` have `start`,
--- `length` and `pitch`. A column covers `1 / zoom` beats from `from`.
function M.miniroll(notes: {types.Note}, width: integer, rows: integer, zoom: number, from?: number): {string}
  from = from or 0
  local g = M.g
  local low, high = 127, 0
  for _, n in ipairs(notes) do
    low, high = math.min(low, n.pitch), math.max(high, n.pitch)
  end
  local levels = rows * 2
  -- Spread a narrow range over at least an octave, so a few notes close
  -- together do not fill the clip from top to bottom.
  local span = math.max(high - low + 1, 1)
  if span > 1 and span < 12 then
    local pad = math.floor((12 - span) / 2)
    low, span = low - pad, 12
  end
  -- Which levels sound in each column.
  local lit: {{integer: boolean}} = {}
  for col = 1, width do
    lit[col] = {}
  end
  for _, n in ipairs(notes) do
    local c0 = math.max(0, math.floor((n.start - from) * zoom + 1e-9))
    local c1 = math.min(width - 1, math.ceil((n.start + n.length - from) * zoom - 1e-9) - 1)
    -- A lone pitch sits in the middle, not at the bottom.
    local level = span == 1 and math.floor(levels / 2) or math.floor((n.pitch - low) / span * levels)
    for col = c0, math.max(c0, c1) do
      if lit[col + 1] then
        lit[col + 1][level] = true
      end
    end
  end
  local out: {string} = {}
  for row = 0, rows - 1 do
    local upper, lower = levels - 1 - 2 * row, levels - 2 - 2 * row
    local cells: {string} = {}
    for col = 1, width do
      local up, down = lit[col][upper], lit[col][lower]
      cells[col] = up and down and g.full or up and g.upper or down and g.lower or " "
    end
    out[row + 1] = table.concat(cells)
  end
  return out
end

--- How far a sample of size `a` (0 to 1) goes up a waveform, 0 to 1. With
--- `paw.opt.wave_scale` "linear", the size does not change, and a kick shows
--- over a hat. With `"db"`, the scale is in decibels from -48, and quiet
--- sounds show.
function M.wave_reach(a: number): number
  a = math.min(math.abs(a), 1)
  if opt.wave_scale ~= "db" then
    return a
  end
  return a <= 1e-4 and 0 or paw.util.clamp((20 * math.log10(a) + 48) / 48, 0, 1)
end
local wave_reach = M.wave_reach

--- Peaks (`{ min, max }` pairs from -1 to 1, one for each column) as a
--- waveform of `rows` text rows. Each column goes from its lowest to its
--- highest sample around the middle of the rows, in eighths of a row.
--- Returns the rows as text. It also returns, for each row, its runs
--- `{ column, text, mark }` of cells with the same mark. The column counts
--- from 0. The text of a run has the style of the mark, `nil` for none.
--- "flip" is for cells whose upper part is the wave. Such a cell is an
--- eighth block in reverse video, because blocks only grow from the bottom.
--- "clip" is for a column that reaches full scale, and `clipflip` for both.
function M.waveform(peaks: {{number}}, rows: integer): {string}, {{WaveRun}}
  local g = M.g
  local plain = opt.ascii
  local half = rows * 4
  local cells: {{string}} = {}
  local flips: {{boolean}} = {}
  local clips: {boolean} = {}
  for row = 1, rows do
    cells[row], flips[row] = {}, {}
  end
  local count = 0
  for i, p in ipairs(peaks) do
    count = i
    local low, high = p[1], p[2]
    clips[i] = high >= 0.999 or low <= -0.999
    local lit = high - low > 1e-4 or math.abs(high) > 1e-4
    -- Eighths from the top of the rows, the wave covering [top, bottom).
    local top = math.floor(half - (high < 0 and -1 or 1) * wave_reach(high) * half + 0.5)
    local bottom = math.floor(half - (low < 0 and -1 or 1) * wave_reach(low) * half + 0.5)
    if bottom <= top then
      top, bottom = math.min(top, rows * 8 - 1), math.min(top, rows * 8 - 1) + 1
    end
    for row = 1, rows do
      local from, to = math.max(top - (row - 1) * 8, 0), math.min(bottom - (row - 1) * 8, 8)
      local cell, flip = " ", false
      if lit and to > from then
        if from == 0 and to == 8 then
          cell = g.full
        elseif to == 8 then
          cell = g.eighths[8 - from]
        elseif from == 0 then
          cell, flip = plain and g.upper or g.eighths[8 - to], not plain
        else
          -- Floating in the middle row: a thin line, or a half block.
          local mid = (from + to) / 2
          cell = to - from >= 5 and g.full
            or to - from <= 2 and (plain and g.peak or "─")
            or mid < 4 and g.upper
            or g.lower
        end
      end
      cells[row][i], flips[row][i] = cell, flip
    end
  end
  local out: {string} = {}
  local runs: {{WaveRun}} = {}
  for row = 1, rows do
    local line: {WaveRun} = {}
    local run: WaveRun
    for i = 1, count do
      local cell = cells[row][i]
      local mark: string
      if cell ~= " " then
        mark = (clips[i] and "clip" or "") .. (flips[row][i] and "flip" or "")
        if mark == "" then
          mark = nil
        end
      end
      if run and run.mark == mark then
        run.cells[#run.cells + 1] = cell
      else
        run = {column = i - 1, cells = {cell}, mark = mark}
        line[#line + 1] = run
      end
    end
    for _, r in ipairs(line) do
      r.text, r.cells = table.concat(r.cells), nil
    end
    out[row], runs[row] = table.concat(cells[row]), line
  end
  return out, runs
end

local function utf8_char(code: integer): string
  if code < 0x800 then
    return string.char(0xC0 + math.floor(code / 64), 0x80 + code % 64)
  end
  return string.char(0xE0 + math.floor(code / 4096), 0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
end

local dots: {{integer}} = {{0x01, 0x02, 0x04, 0x40}, {0x08, 0x10, 0x20, 0x80}}
local lines3: {string: {string}} = {unicode = {"▁", "─", "▔"}, ascii = {"_", "-", "'"}}

--- How paw draws curves in cells: "sextant", "braille" or "line", from
--- `paw.opt.curve_glyphs`. `paw.opt.braille = false` and `paw.opt.ascii`
--- both mean "line". `paw.opt.ascii` wins over all, and uses ASCII characters.
function M.curve_glyphs(): string
  if opt.ascii or opt.braille == false then
    return "line"
  end
  local kind = opt.curve_glyphs
  if kind == "braille" or kind == "line" then
    return kind
  end
  return "sextant"
end

--- The character for a set of sextants (U+1FB00 to U+1FB3B, two columns
--- by three rows): bits 1 to 32 are top left, top right, middle left,
--- middle right, bottom left, bottom right. The patterns that are not in
--- that block are a space, the left half, the right half and the full block.
function M.sextant(bits: integer): string
  if bits == 0 then
    return " "
  end
  if bits == 21 then
    return "▌"
  end
  if bits == 42 then
    return "▐"
  end
  if bits == 63 then
    return "█"
  end
  local n = bits - 1
  if bits > 21 then
    n = n - 1
  end
  if bits > 42 then
    n = n - 1
  end
  local cp = 0x1FB00 + n
  return string.char(
    0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64, 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64
  )
end

--- A braille character from its eight dots: bit k is dot k + 1.
function M.braille(bits: integer): string
  return utf8_char(0x2800 + bits)
end

--- A connected line over a grid of cells, for a curve. `y(sx)` gives the
--- row of the line from the top, in `sub` rows for each cell (3 for
--- sextants, 4 for braille). `sx` counts from 0, with two samples for each
--- cell. `y(sx)` gives nil for no line, and there are `samples` of them.
--- The function fills a jump from the last row to this row, to keep the
--- line connected. Returns `{ [row * width + col] = bits }`, the bits as
--- `M.sextant` or `M.braille` take them.
function M.trace(width: integer, samples: integer, y: Row, sub: integer, kind: string): {integer: integer}
  local cells: {integer: integer} = {}
  local last: integer
  for sx = 0, samples - 1 do
    local row = y(sx)
    if row then
      local a, b = row, row
      if last then
        a, b = math.min(row, last), math.max(row, last)
        if math.abs(row - last) > 1 then
          if row > last then
            a = last + 1
          else
            b = last - 1
          end
        end
      end
      local side = sx % 2
      for r = a, b do
        local bit: integer
        if kind == "braille" then
          bit = dots[side + 1][r % 4 + 1]
        else
          bit = (2 ^ ((r % 3) * 2 + side)) as integer
        end
        local key = math.floor(r / sub) * width + math.floor(sx / 2)
        cells[key] = (cells[key] or 0) + bit -- each cell and side comes from one sample
      end
      last = row
    end
  end
  return cells
end

--- Draw a curve as a thin line over `rows` rows of a buffer, from row `y`
--- down. `value(i)` gives the height, from 0 at the bottom to 1 at the top,
--- at point `i`, with two points for each column. The function changes only
--- the cells on the line. It uses sextants (a connected line), braille dots
--- or lines at three heights a row, as `M.curve_glyphs()` tells.
function M.curve(buf: Buf, y: integer, rows: integer, value: Height, style?: Style)
  local kind = M.curve_glyphs()
  if kind == "line" then
    local set = opt.ascii and lines3.ascii or lines3.unicode
    for col = 0, buf.width - 1 do
      local v = value(col * 2)
      if v then
        local level = math.min(rows * 3 - 1, math.floor(paw.util.clamp(v, 0, 1) * rows * 3))
        buf:text(col, y + rows - 1 - math.floor(level / 3), set[level % 3 + 1], style)
      end
    end
    return
  end
  local sub = kind == "braille" and 4 or 3
  local steps = rows * sub
  local cells = M.trace(
    buf.width,
    buf.width * 2,
    function(sx: integer): integer
      local v = value(sx)
      if not v then
        return nil
      end
      return steps - 1 - math.min(steps - 1, math.floor(paw.util.clamp(v, 0, 1) * steps))
    end,
    sub,
    kind
  )
  local glyph = kind == "braille" and M.braille or M.sextant
  for key, bits in pairs(cells) do
    buf:text(key % buf.width, y + math.floor(key / buf.width), glyph(bits), style)
  end
end

-- Piano rolls -----------------------------------------------------------------

--- One row of a keyboard on its side, `width` cells wide, for the left edge
--- of a piano roll. Black keys are short. The Cs have their names, and the
--- pitch of the cursor has its name too.
function M.piano_key(buf: Buf, row: integer, pitch: integer, cursor: boolean, width: integer, name?: string)
  local music = paw.music
  local step = pitch % 12
  if music.is_black(pitch) then
    buf:fill(0, row, width - 2, 1, " ", "PianoBlack")
    buf:fill(width - 2, row, 2, 1, " ", "PianoWhite")
  else
    -- Two white keys with no black one between them get a line instead.
    buf:fill(0, row, width, 1, (step == 0 or step == 5) and (opt.ascii and "_" or "▁") or " ", "PianoWhite")
    if step == 0 and not name then
      buf:text(1, row, music.name(pitch), "PianoC")
    end
  end
  -- A key the instrument names (a drum, a keyswitch) shows its name.
  if name then
    buf:text(0, row, paw.util.fit(name, width - 1), "PianoC")
  end
  if cursor then
    buf:text(0, row, paw.util.fit(music.name(pitch), width - 1) .. " ", "PianoCursor")
  end
end

--- The bars and beats from `from` for `span` beats, as the project counts
--- them. `{ beat = b, bar = n }` is a bar line (n from 1), and
--- `{ beat = b }` is a beat inside a bar. Bar lines come from
--- `paw.time.bar_start`, so a change of time signature moves them.
function M.bar_lines(from: number, span: number): {BarLine}
  -- From the tempo map: bars, and the beats of the signature in each.
  local out: {BarLine} = {}
  for _, line in ipairs(paw.tempo.lines(from - 1e-9, from + span + 1e-9)) do
    out[#out + 1] = line.index == 0 and {beat = line.beat, bar = line.bar} or {beat = line.beat}
  end
  return out
end

--- Where a view scrolls to for a move of its cursor to `target`, a beat, or
--- nil when the move leaves the scroll to the caller. A step (`jumped` is
--- false) is left to the caller, which scrolls just enough. A jump (it went
--- into the jump list) to a target that is off screen, or in the last quarter
--- of the view, puts the target at the left margin (`paw.opt.jumpview` "left",
--- `paw.opt.jumpmargin` columns) or in the middle ("center"). `span` is the
--- beats shown, `zoom` the columns a beat.
function M.jump_scroll(target: number, scroll: number, span: number, zoom: number, jumped: boolean): number
  if not jumped then
    return nil
  end
  if target >= scroll and target < scroll + span * 0.75 then
    return nil
  end
  local at = opt.jumpview == "center" and span / 2 or (opt.jumpmargin as number) / zoom
  return target - at
end

--- Write the numbers of a ruler above a roll that shows `span` beats from
--- `scroll`, at `zoom` columns for each beat. Bars have the numbers of the
--- project (`origin` is the project beat of the beat 0 of the roll). Beats
--- between them are ticks. Returns the positions of the lines, as
--- `{ x, bar }`, for the rows below.
function M.beats(ruler: Buf, scroll: number, span: number, zoom: number, origin: number): {RulerLine}
  local g = M.g
  local lines: {RulerLine} = {}
  local every = math.max(1, math.ceil(4 / (paw.time.bar(origin + scroll) * zoom)))
  local free = 0
  for _, line in ipairs(M.bar_lines(origin + scroll, span)) do
    local at = math.floor((line.beat - origin - scroll) * zoom + 0.5)
    lines[#lines + 1] = {x = at, bar = line.bar ~= nil, beat = line.beat - origin}
    if line.bar then
      if (line.bar - 1) % every == 0 and at >= free then
        free = at + ruler:text(at, 0, tostring(line.bar), "RulerBar") + 1
      end
    elseif zoom >= 2 and at >= free then
      ruler:text(at, 0, g.tick, "RulerTick")
    end
  end
  return lines
end

--- A row of keys and their actions, for a line of hints: `{ { "o", "new track" }, ... }`,
--- with a faint dot between them. `? keys` is always the last when it is in
--- the list. Returns the columns used. The entries that do not fit are not shown.
function M.keys(buf: Buf, x: integer, y: integer, entries: {KeyHint}, width: integer, groups?: string): integer
  local g = M.g
  local key, text, sep_style = "KeyBarKey", "KeyBarText", "KeyBarSep"
  if groups == "FloatFooter" then
    key, text, sep_style = "FooterKey", "FooterText", "FooterSep"
  end
  local list: {KeyHint} = {}
  local last: KeyHint
  for _, entry in ipairs(entries) do
    if entry[1] == "?" then
      last = entry
    else
      list[#list + 1] = entry
    end
  end
  local room = width
  if last then
    room = room - api.str_width(last[1]) - api.str_width(last[2]) - 4
  end
  local at = x
  local sep = " " .. g.dot .. " "
  local function put(entry: KeyHint)
    if at > x then
      at = at + buf:text(at, y, sep, sep_style)
    end
    at = at + buf:text(at, y, entry[1], key)
    at = at + buf:text(at, y, " " .. entry[2], text)
  end
  for _, entry in ipairs(list) do
    local need = api.str_width(entry[1]) + api.str_width(entry[2]) + 1 + (at > x and 3 or 0)
    if at + need > x + room then
      break
    end
    put(entry)
  end
  if last then
    put(last)
  end
  return at - x
end

M.use_glyphs()

return M
