-- The strip under the piano roll: the notes' velocities, as the roll draws
-- them, or one controller's moves (the pitch wheel, modulation,
-- expression, the sustain pedal), drawn over with the pointer. A click on
-- the strip's name, at its left, chooses what it shows.
--
-- Over a controller: the left button held draws it, a press on a move's
-- head (the top of its bar) chooses it (Ctrl or Shift adds it or takes it
-- out) and a drag moves the chosen, Ctrl and a drag chooses the moves in a
-- box, the right button dragged draws a straight line and clicked opens
-- the menu. Each through `paw.frontend.act`.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local seats = require("paw.seats")
local util = require("paw.util")
local theme = require("paw.theme")
local mouse = require("paw.mouse")
local axis = require("paw.axis")
local menus = require("paw.mouse_menus")
local type types = require("paw.types")
local type objects = require("paw.objects")
local type contracts = require("paw.contracts")
local type CurvesModule = require("paw.curves")
local type Roll = require("paw.views.pianoroll")

local type Buf = contracts.Buf
local type MouseEvent = contracts.MouseEvent
local type PianoRoll = Roll.PianoRoll
local type Kind = Roll.StripKind
local type Grab = Roll.Grab

-- The declaration of `paw` (paw.d.tl) does not name the types of this
-- module, so the typed global `paw` is in scope here.
local view = paw.ui.views:get("pianoroll") as PianoRoll
local A = paw.frontend.act

--- A controller move shown on the strip, and its place among the clip's.
local record Shown
  c: types.Control
  place: integer
end

--- What `M.picture` draws: the moves shown, the places chosen, the kind of
--- controller, the roll's scroll and zoom, the clip's length and the
--- track's colour.
local record Picture
  list: {Shown}
  chosen: {integer: boolean}
  kind: string
  scroll: number
  zoom: number
  length: number
  color: string
end

local record M
  type Picture = Picture
  --- What the strip can show, in the order the menu lists them.
  kinds: {Kind}
  shown: function(): Kind
  show: function(kind?: string, number?: integer)
  picture: function(g: contracts.Painter, px: contracts.StripPixels, o: Picture)
  press: function(self: PianoRoll, e: MouseEvent, clip: objects.Clip): boolean
end
M.kinds = {
  {label = "Velocity", short = "vel"},
  {label = "Pitch wheel", short = "bend", kind = "bend"},
  {label = "Modulation", short = "mod", kind = "cc", number = 1},
  {label = "Expression", short = "expr", kind = "cc", number = 11},
  {label = "Sustain pedal", short = "ped", kind = "cc", number = 64},
}

-- What the strip shows, for each seat: one of `M.kinds`.
local shown = M.kinds[1]
seats.keep(
  "pianoroll.strip",
  function(): Kind return shown end,
  function(s: Kind) shown = s end,
  function(): Kind return M.kinds[1] end
)

--- What the strip shows now: `{ label, short, kind, number }`, `kind` nil
--- for the velocities.
function M.shown(): Kind
  return shown
end

--- Show the velocities (nil) or a controller: "bend", or "cc" with its number.
function M.show(kind?: string, number?: integer)
  for _, k in ipairs(M.kinds) do
    if k.kind == kind and k.number == number then
      shown = k
    end
  end
  api.ui_redraw()
end

-- Drawing ----------------------------------------------------------------------------------

--- The strip's picture: `o.list` the moves shown (`{ c, place }` each),
--- `o.chosen` the places chosen, `o.kind` "bend" or "cc", `o.scroll` and
--- `o.zoom` the roll's, `o.length` the clip's, `o.color` the track's.
function M.picture(g: contracts.Painter, px: contracts.StripPixels, o: Picture)
  local P = theme.palette
  local ppb = o.zoom * px.cell.w
  local function X(beat: number): number
    return (beat - o.scroll) * ppb
  end
  -- From the first move (the wheel rests in the middle before it) to the clip's end.
  local first = o.list[1]
  local x0 = o.kind == "bend" and 0 or (first and math.max(0, math.floor(X(first.c.start))) or px.w)
  local x1 = math.min(px.w, math.floor(X(o.length) + 0.5))
  if x1 <= x0 then
    return
  end
  local points: {CurvesModule.Point} = {}
  if o.kind == "bend" then
    points[1] = {beat = o.scroll - 1, value = 0.5, shape = "hold"}
  end
  for _, item in ipairs(o.list) do
    points[#points + 1] = {beat = item.c.start, value = paw.controls.fraction(o.kind, item.c.value), shape = "hold"}
  end
  local part: contracts.StripPixels = {w = x1 - x0, h = px.h, cell = px.cell}
  local _, Y = paw.plot.curve(
    g:sub(x0, 0, x1 - x0, px.h),
    part,
    {
      points = points,
      from = o.scroll + x0 / ppb,
      pixels_per_beat = ppb,
      color = o.color,
      guides = false,
      markers = false,
      grid = false,
      fill = 0.3,
    }
  )
  for _, item in ipairs(o.list) do
    local x = X(item.c.start)
    if x >= x0 - 3 and x <= x1 + 3 then
      local y = Y(paw.controls.fraction(o.kind, item.c.value))
      g:rect(x - 2, y - 2, 4, 4, {fill = o.chosen[item.place] and P.bright or o.color})
    end
  end
end

--- The controller's bars over the strip: each column as high as the value
--- that holds there, the columns where a move is lit, the chosen brighter.
local function draw(self: PianoRoll, buf: Buf)
  local g = self.geometry
  local clip = self:clip()
  if not (shown.kind and clip and g and g.vel and g.vel > 0) then
    return
  end
  local eighths = paw.draw.g.eighths
  local top, rows, keys = g.head + g.lines, g.vel, g.keys
  local tw = buf.width - keys
  -- Its name at the left is the roll's (a button that chooses what it shows).
  buf:fill(keys, top, tw, rows, " ", "VelocityLane")
  local lane = buf:sub(keys, top, tw, rows)
  local track = api.track_get(api.clip_get(clip.id).track)
  local hue = paw.draw.track_hue(track)
  local list: {Shown} = {}
  local chosen: {integer: boolean} = {}
  for _, place in ipairs(paw.controls.chosen(clip.id)) do
    chosen[place] = true
  end
  for place, c in ipairs(clip:controls()) do
    if paw.controls.is(c, shown.kind, shown.number) then
      list[#list + 1] = {c = c, place = place}
    end
  end
  local length = clip.length
  -- In pixels under the cells, where the terminal shows them: the value
  -- held from each move as a line with the area under it, and a mark on
  -- each move, the chosen brighter.
  local scroll, zoom, kind = self.scroll, g.zoom, shown.kind
  local pictured = lane:strip(
    0,
    0,
    tw,
    rows,
    {
      key = "pianoroll:strip",
      under = true,
      draw = function(gp: contracts.Painter, px: contracts.StripPixels)
        M.picture(
          gp,
          px,
          {
            list = list,
            chosen = chosen,
            kind = kind,
            scroll = scroll,
            zoom = zoom,
            length = length,
            color = paw.draw.track_colour(track),
          }
        )
      end,
    }
  )
  if pictured then
    return
  end
  -- In cells: each column as high as the value that holds there.
  local at = 1
  local value: number = shown.kind == "bend" and 0 or nil
  local ax = g.axis
  for x = 0, tw - 1 do
    local from, to = ax:cell_span(x)
    -- Nothing plays past the clip's end.
    if from >= length then
      break
    end
    local here: Shown
    while list[at] and list[at].c.start < to - 1e-9 do
      value = list[at].c.value
      if list[at].c.start >= from - 1e-9 then
        here = list[at]
      end
      at = at + 1
    end
    if value then
      local level = paw.controls.fraction(shown.kind, value) * rows * 8
      local style = here and (chosen[here.place] and "Bright" or hue.fg) or "Faint"
      for row = 0, rows - 1 do
        local amount = level - (rows - 1 - row) * 8
        if amount >= 1 then
          lane:text(x, row, eighths[math.min(8, math.floor(amount))], style)
        end
      end
    end
  end
end

-- The roll draws the strip after its own parts, and the line of a gesture
-- under way over it.
view.strip = {
  shown = M.shown,
  draw = function(self: PianoRoll, buf: Buf)
    draw(self, buf)
    local gesture = mouse.gesture() as Grab
    if gesture and gesture.strip then
      gesture.strip(self, buf)
    end
  end,
}

-- The pointer ------------------------------------------------------------------------------

--- The menu of what the strip shows, at `where` on the screen.
local function choose_kind(where: contracts.MenuOptions)
  local items: {contracts.MenuEntry} = {}
  for _, k in ipairs(M.kinds) do
    items[#items + 1] = {label = k.label, checked = k == shown, run = function() M.show(k.kind, k.number) end}
  end
  paw.ui.menu(items, where)
end

--- What a press on the strip's controllers works with: the roll, the
--- clip, the controller shown, where the strip is, and the beat of a
--- column and the value (a fraction) of a row.
local record Press
  view: PianoRoll
  clip: objects.Clip
  kind: string
  number: integer
  top: integer
  rows: integer
  beat: function(x: number): number
  fraction: function(y: number): number
end

--- The right button: dragged, a straight line of moves from the press to
--- where it is let go; clicked, the menu of the strip.
local function press_line(p: Press, e: MouseEvent, where: contracts.MenuOptions)
  local x0, y0 = math.floor(e.x), math.floor(e.y)
  local id = p.clip.id
  local line: Grab = {
    strip = function(_: PianoRoll, buf: Buf)
      local d = (mouse.gesture() as Grab).d
      if d and d.moved then
        buf:text(x0, y0, paw.draw.g.point, "MouseBox")
        buf:text(math.floor(d.x), util.clamp(math.floor(d.y), p.top, p.top + p.rows - 1), paw.draw.g.point, "MouseBox")
      end
    end,
    drag = function(d: MouseEvent) (mouse.gesture() as Grab).d = d end,
    up = function(u: MouseEvent)
      if not u.moved then
        return paw.ui.menu(menus.strip(id, p.kind, p.number), where)
      end
      A.line_controls(id, p.kind, p.number, p.beat(x0), p.fraction(y0), p.beat(u.x), p.fraction(u.y), mouse.has(u, "S"))
    end,
  }
  mouse.grab(e, line)
end

--- The place of the move whose head is under the pointer, or nil: the top
--- of its bar, in the cell a terminal draws it in; within half a cell of
--- it in a window.
local function head_at(p: Press, e: MouseEvent): integer
  local g = p.view.geometry
  local ax = axis.new(p.view.scroll, g.zoom)
  local tx = e.x - g.keys
  local function on_head(c: types.Control): boolean
    local x = ax:exact(c.start)
    local f = paw.controls.fraction(p.kind, c.value)
    if e.fine then
      return math.abs(tx - x) <= 0.5 and math.abs(e.y - (p.top + p.rows * (1 - f))) <= 0.5
    end
    local level = f * p.rows * 8
    return ax:x_of(c.start) == tx and e.y == p.top + p.rows - 1 - math.max(0, math.floor((level - 1) / 8))
  end
  for place, c in ipairs(p.clip:controls()) do
    if paw.controls.is(c, p.kind, p.number) and on_head(c) then
      return place
    end
  end
  return nil
end

--- A press on the head of a move: chooses it (Ctrl turns it over, Shift
--- adds it), and a drag without either moves the chosen.
local function press_head(p: Press, e: MouseEvent, place: integer)
  local id, ax = p.clip.id, axis.new(p.view.scroll, p.view.geometry.zoom)
  local toggling = mouse.has(e, "C") or mouse.has(e, "S")
  if toggling then
    A.select_control(id, place, mouse.has(e, "C") and "toggle" or "add")
  else
    local among = false
    for _, chosen in ipairs(paw.controls.chosen(id)) do
      among = among or chosen == place
    end
    if not among then
      A.select_control(id, place, "only")
    end
  end
  mouse.grab(
    e,
    {
      drag = function(d: MouseEvent)
        mouse.hint(string.format("moving the chosen moves by %g beats", math.floor(ax:beats(d.dx) * 100 + 0.5) / 100))
      end,
      up = function(u: MouseEvent)
        if u.moved and not toggling then
          A.move_controls(id, ax:beats(u.dx), -u.dy / p.rows, mouse.has(u, "S"))
        end
      end,
    }
  )
end

--- Ctrl and a drag: a box that chooses the moves in it (Shift adds them).
local function press_box(p: Press, e: MouseEvent)
  local x0, y0 = e.x, e.y
  -- The last column a box takes in: a terminal's whole column, a
  -- window's pointer where it is.
  local reach = e.fine and 0 or 1
  mouse.grab(
    e,
    {
      up = function(u: MouseEvent)
        local a, b = math.min(x0, u.x), math.max(x0, u.x)
        A.select_controls(
          p.clip.id,
          p.kind,
          p.number,
          p.beat(a),
          p.fraction(math.max(y0, u.y)),
          p.beat(b + reach),
          p.fraction(math.min(y0, u.y)),
          mouse.has(u, "S") and "add" or "only"
        )
      end,
    }
  )
end

--- A drag of the left button: the moves under the stroke get its values.
local function press_draw(p: Press, e: MouseEvent)
  local stroke: {{number, number}} = {{p.beat(e.x), p.fraction(e.y)}}
  mouse.grab(
    e,
    {
      drag = function(d: MouseEvent)
        stroke[#stroke + 1] = {p.beat(d.x), p.fraction(d.y)}
        local f = stroke[#stroke][2]
        mouse.hint(
          p.kind == "bend" and string.format("bend %d", math.floor(8192 * (f * 2 - 1) + 0.5))
            or string.format("value %d", math.floor(127 * f + 0.5))
        )
      end,
      up = function() A.draw_controls(p.clip.id, p.kind as types.ControlType, p.number, stroke) end,
    }
  )
end

--- A press on the strip, `e` in the view's cells (fractions of them from a
--- window, `e.fine`): the strip's name opens the menu of what it shows;
--- the rest is drawn on. Returns whether the press was taken here.
function M.press(self: PianoRoll, e: MouseEvent, clip: objects.Clip): boolean
  local g = self.geometry
  local where: contracts.MenuOptions = {x = math.floor(e.x + (e.view_x or 0)), y = math.floor(e.y + (e.view_y or 0))}
  -- The strip's name, left of the strip: the menu of what it shows.
  if e.x < g.keys then
    if e.button == "left" or e.button == "right" then
      mouse.grab(
        e,
        {
          up = function(u: MouseEvent)
            if not u.moved then
              choose_kind(where)
            end
          end,
        }
      )
    end
    return true
  end
  -- The velocity strip takes the press itself (paw/views/pianoroll_mouse.tl).
  if not shown.kind then
    return false
  end
  local top, rows = g.head + g.lines, g.vel
  -- A terminal's cell at its middle, a window's pointer where it is.
  local half = e.fine and 0 or 0.5
  local p: Press = {
    view = self,
    clip = clip,
    kind = shown.kind,
    number = shown.number,
    top = top,
    rows = rows,
    beat = function(x: number): number return axis.new(self.scroll, g.zoom):beat_of(x - g.keys) end,
    fraction = function(y: number): number return util.clamp(1 - (y - top + half) / rows, 0, 1) end,
  }
  if e.button == "right" then
    press_line(p, e, where)
    return true
  end
  if e.button ~= "left" then
    return true
  end
  local place = head_at(p, e)
  if place then
    press_head(p, e, place)
  elseif mouse.has(e, "C") then
    press_box(p, e)
  else
    press_draw(p, e)
  end
  return true
end

return M
