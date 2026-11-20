-- A drawing buffer: a rectangle of the screen that a view draws into.
--
--   buf:text(x, y, text, style)        draw text, returns the columns it takes
--   buf:fill(x, y, w, h, char, style)  restyle an area; `char` overwrites it too
--   buf:sub(x, y, w, h)                a buffer for part of this one
--   buf:surface(x, y, w, h, name)      keep an area for a view's pixels
--   buf:strip(x, y, w, h, opts)        keep an area for pixels a function draws
--   buf:mark(role, x, y, w, h, props)  a role there: a fader, a button (paw/roles.tl)
--   buf:hit(x, y, w, h, action)        a region the pointer acts on
--   buf:plane(x, y, w, h, opts)        an area placing what is marked in it by a domain (beats, pitches)
--   buf:columns(widths, gap)           buffers side by side, a width each
--   buf.width, buf.height
--
-- Coordinates count cells from 0 at the buffer's top-left corner, and
-- anything drawn outside the buffer is clipped. A style is the name of a
-- highlight group, a table such as `{ fg = "#ff9e64", bold = true }`, or nil
-- to keep the colours already there.
--
-- `mark`, `hit` and `plane` are paw/roles.tl's, which puts them here when
-- it loads: it needs the type of a buffer, and this file nothing of it.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")

-- What this module reads of `paw`, which paw/init.lua makes. The global
-- `paw` (runtime/types/paw.d.tl) does not name this module, which is
-- `paw.ui.Buf` of paw/ui.tl: so its local has a name of its own. paw/ui.tl
-- names this module's type, so this one declares only the part of it that
-- it calls.
local record Ui
  surface: function(buf: Buf, x: number, y: number, w: number, h: number, name?: string): boolean
  strip: function(buf: Buf, x: number, y: number, w: number, h: number, opts: contracts.StripOptions): boolean
end
local record Runtime is partial.Paw
  ui: Ui
end
local runtime = (_G as {string:Runtime}).paw
local unpack = (_G as {string:function({Buf}, integer, integer): Buf...}).unpack

local grid_text, grid_fill = api.grid_text, api.grid_fill
local floor, max, min = math.floor, math.max, math.min

--- A buffer: where it is on the screen (`x`, `y`, `width`, `height`), and
--- the part of the screen it may draw on (`cx`, `cy`, `cw`, `ch`).
local record Buf is contracts.Buf
  cx: integer
  cy: integer
  cw: integer
  ch: integer
  root: function(width: integer, height: integer): Buf
  sub: function(self: Buf, x: number, y: number, w: number, h: number): Buf
  mark: function(self: Buf, role: string, x: number, y: number, w: number, h: number, props?: contracts.MarkProps): Buf
  hit: function(self: Buf, x: number, y: number, w: number, h: number, action: contracts.HitAction)
  plane: function(self: Buf, x: number, y: number, w: number, h: number, opts: contracts.PlaneOptions): contracts.Plane
  columns: function(self: Buf, widths: {integer | string}, gap?: integer): Buf...
end

-- The class is the metatable of its buffers, as in Lua.
local Meta = Buf as metatable<Buf>
Meta.__index = Buf

local function new(x: integer, y: integer, width: integer, height: integer, cx: integer, cy: integer, cw: integer, ch: integer): Buf
  return setmetatable({ x = x, y = y, width = width, height = height, cx = cx, cy = cy, cw = cw, ch = ch } as Buf, Meta)
end

--- The buffer that covers a whole screen of the given size.
function Buf.root(width: integer, height: integer): Buf
  return new(0, 0, width, height, 0, 0, width, height)
end

--- Write `text` at column `x`, row `y` of this buffer in highlight group
--- `style`, clipped to the buffer. Returns the number of columns written.
function Buf:text(x: number, y: number, text: string, style?: contracts.Style): integer
  return grid_text(self.x + x, self.y + y, text, style, self.cx, self.cy, self.cw, self.ch)
end

--- Fill a `w` by `h` area at `x`, `y` with `char` in `style`, clipped.
function Buf:fill(x: number, y: number, w: number, h: number, char?: string, style?: contracts.Style)
  grid_fill(self.x + x, self.y + y, w, h, char, style, self.cx, self.cy, self.cw, self.ch)
end

--- Keep an area for the pixels of a view that paints (`name`, by default
--- the view that paw draws), where the terminal shows images. Its `paint`
--- draws there at the cell size of the terminal, after paw draws the
--- screen. The cells stay blank. False where the terminal shows only cells.
--- Then the view draws them:
---   if buf:surface(0, 1, buf.width, buf.height - 1) then return end
function Buf:surface(x: number, y: number, w: number, h: number, name?: string): boolean
  return runtime.ui.surface(self, x, y, w, h, name)
end

--- Keep an area for pixels that `opts.draw(g, px)` draws, where the
--- terminal shows images. `g` is a painter of `paw.canvas`. `px` is
--- `{ w, h, cell = { w, h }, fg, bg, view }`: the size of the strip, the
--- cell of the terminal in pixels, and its colors. For a strip that is
--- partly off its window, `view` is the part that shows (x, y, w, h). paw
--- calls it after it draws the screen. `opts.key` names the strip, and paw
--- keeps images by this name. For a view that can be in two windows, put
--- the id of the window in it. The default is the view and its window.
--- With `opts.under`, the cells that the view draws there stay above the
--- picture (its cursor, labels, the playhead). If not, they are blank.
--- False where there are no pixels (`paw.opt.graphics` off, a terminal
--- without images, tmux, or a terminal that cannot put text over an image).
--- Then the view draws cells there:
---   local pictured = plot:strip(0, 0, plot.width, plot.height, {
---     key = "curve:" .. win.id, under = true,
---     draw = function(g, px) paw.plot.curve(g, px, { ... }) end,
---   })
function Buf:strip(x: number, y: number, w: number, h: number, opts: contracts.StripOptions): boolean
  return runtime.ui.strip(self, x, y, w, h, opts)
end

--- Buffers side by side across this buffer, each with a width from the
--- left, with `gap` columns between them (0 by default). A width of "*"
--- takes the space that the others leave. paw does not make the buffers
--- that do not fit.
---   local name, body = buf:columns({ 12, "*" })
function Buf:columns(widths: {integer | string}, gap?: integer): Buf...
  gap = gap or 0
  local fixed, flexible = 0, 0
  for _, w in ipairs(widths) do
    if w is string then flexible = flexible + 1 else fixed = fixed + w end
  end
  local rest = max(0, self.width - fixed - gap * (#widths - 1))
  local out: {Buf} = {}
  local x = 0
  for i, w in ipairs(widths) do
    local width = w is string and floor(rest / flexible) or w as integer
    if x >= self.width then break end
    out[i] = self:sub(x, 0, min(width, self.width - x), self.height)
    x = x + width + gap
  end
  return unpack(out, 1, #widths)
end

--- A buffer for the area `x`, `y`, `w` by `h` of this one, clipped to it.
function Buf:sub(x: number, y: number, w: number, h: number): Buf
  local x0, y0, w0, h0 = floor(self.x + x), floor(self.y + y), max(0, floor(w)), max(0, floor(h))
  local cx, cy = max(x0, self.cx), max(y0, self.cy)
  local right, bottom = min(x0 + w0, self.cx + self.cw), min(y0 + h0, self.cy + self.ch)
  return new(x0, y0, w0, h0, cx, cy, max(0, right - cx), max(0, bottom - cy))
end

return Buf
